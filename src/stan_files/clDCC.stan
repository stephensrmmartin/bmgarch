// DCC-Parameterization
functions { 
#include /functions/cov2cor.stan
}

data {
#include /data/data.stan
}

transformed data {
  // Obtain mean and sd over TS for prior in arma process phi0                                                                                                                                                 
  vector[nt] rts_m;
  vector[nt] rts_sd;
 
#include /transformed_data/xh_marker.stan
 
  for ( i in 1:nt ){
    rts_m[i] = mean(rts[,i]);
    rts_sd[i] = sd(rts[,i]);
  }
}

parameters {
  // ARMA parameters 
#include /parameters/arma.stan
  // predictor for H
#include /parameters/predH.stan

  // GARCH h parameters on variance metric
  vector[nt] c_h; // variance on log metric 
  // vector<lower = 0,  upper = 1 >[nt] a_h[Q];
  // vector<lower = 0,  upper = 1 >[nt] b_h[P]; // TODO actually: 1 - a_h, across all Q and P...
  matrix<lower = 0, upper = 1>[nt, nt] a_h[Q];
  matrix<lower = 0, upper = .9>[nt, nt] b_h[P];
  // GARCH q parameters 
  real<lower=0, upper = 1 > a_q; // 
  real<lower=0, upper = (1 - a_q) > b_q; //
  corr_matrix[nt] S;  // DCC keeps this constant 
  // Qr1 init
  cov_matrix[nt] Qr1_init;
  // D1 init
  vector<lower = 0>[nt] D1_init;
  // u1 init
  vector[nt] u1_init;

  real< lower = 2 > nu; // nu for student_t

}

transformed parameters {
  cov_matrix[nt] H[T];
  corr_matrix[nt] R[T];
  row_vector[nt] rr[T-1];
  vector[nt] mu[T];
  vector[nt] D[T];
  cov_matrix[nt] Qr[T];
  vector[nt] Qr_sdi[T];
  vector[nt] u[T];
  // real<lower = 0> vd[nt];
  // real<lower = 0> ma_d[nt];
  // real<lower = 0> ar_d[nt];  
  row_vector<lower = 0>[nt] vd = rep_row_vector(0, nt);
  row_vector<lower = 0>[nt] ma_d = rep_row_vector(0, nt);
  row_vector<lower = 0>[nt] ar_d = rep_row_vector(0, nt);

  // Initialize t=1
  mu[1,] = phi0;
  u[1,] = u1_init;
  D[1,] = D1_init;
  Qr[1,] = Qr1_init;
  H[1] = Qr[1,];
  R[1] = diag_matrix(rep_vector(1.0, nt));
  Qr_sdi[1] = rep_vector(1.0, nt);

  // iterations geq 2
  for (t in 2:T){
    vd = rep_row_vector(0, nt);
    ma_d = rep_row_vector(0, nt);
    ar_d = rep_row_vector(0, nt);
// Meanstructure model:
#include /model_components/mu.stan


    for (q in 1:min(t - 1, Q)) {
      rr[t-q] = square(rts[t - q] - mu[t - q])';
      // rr[t-q] = ((rts[t - q] - mu[t - q]) .* (rts[t - q] - mu[t - q]))';
      ma_d += rr[t - q] * a_h[q];
    }
    // print("ma_d:",ma_d);

    for (p in 1:min(t - 1, P)) {
      ar_d += square(D[t - p])' * b_h[p];
      // ar_d += (D[t - p] .* D[t - p])' * b_h[p];
    }
    // print("ARd:",ar_d);

    if ( xC_marker >= 1 ) {
      for(d in 1:nt) {
	vd[d] = exp(c_h[d] + beta[d] * xC[t, d] ) + ma_d[d] + ar_d[d];
      }
    } else if ( xC_marker == 0) {
      for(d in 1:nt) {
	vd[d] = exp(c_h[d]')  + ma_d[d] + ar_d[d];
      }
    }
    // print("VD:", vd);
    D[t] = sqrt(vd');
    // print("D[t]:",D[t]);

    // for(d in 1:nt){
    //   vd[d] = 0.0;
    //   ma_d[d] = 0.0;
    //   ar_d[d] = 0.0;
    //   // GARCH MA component
    //   for (q in 1:min( t-1, Q) ) {
    // 	rr[t-q, d] = square( rts[t-q, d] - mu[t-q, d] );
    // 	ma_d[d] = ma_d[d] + a_h[q, d]*rr[t-q, d] ;
    //   }
    //   // GARCH AR component
    //   for (p in 1:min( t-1, P) ) {
    // 	ar_d[d] = ar_d[d] + b_h[p, d]*D[t-p, d]^2;
    //   }

    //   // Predictor on diag (given in xC)
    //   if ( xC_marker >= 1) {
    // 	vd[d] = exp( c_h[d] + beta[d] * xC[t, d] ) + ma_d[d] + ar_d[d];
    //   } else if ( xC_marker == 0) {
    //   	vd[d] = exp( c_h[d] )  + ma_d[d] + ar_d[d];
    //   }

    //   D[t, d] = sqrt( vd[d] );
    // }
    
    u[t,] = diag_matrix(D[t,]) \ (rts[t,]- mu[t,]); // cf. comment about taking inverses in stan manual p. 482 re:Inverses - inv(D)*y = D \ a
    Qr[t,] = (1 - a_q - b_q) * S + a_q * (u[t-1,] * u[t-1,]') + b_q * Qr[t-1,]; // S and UU' define dimension of Qr
    Qr_sdi[t,] = 1 ./ sqrt(diagonal(Qr[t,])); // inverse of diagonal matrix of sd's of Qr
    //    R[t,] = quad_form_diag(Qr[t,], inv(sqrt(diagonal(Qr[t,]))) ); // Qr_sdi[t,] * Qr[t,] * Qr_sdi[t,];
    R[t,] = quad_form_diag(Qr[t,], Qr_sdi[t,]); // Qr_sdi[t,] * Qr[t,] * Qr_sdi[t,];
    H[t,] = quad_form_diag(R[t,],     D[t,]);  // H = DRD; 
    // print("Ht:",H[t]);
  }
}
model {
  // priors
  to_vector(beta) ~ std_normal();
  to_vector(c_h) ~ std_normal();
  // Prior for initial state
  Qr1_init ~ wishart(nt + 1.0, diag_matrix(rep_vector(1.0, nt)) );
  to_vector(D1_init) ~ lognormal(0, 1);
  to_vector(u1_init) ~ std_normal();
  // Prior on nu for student_t
  //if ( distribution == 1 )
  nu ~ normal( nt, 50 );
  to_vector(theta) ~ std_normal();
  to_vector(phi) ~ std_normal();
  phi0 ~ multi_normal(rts_m, diag_matrix( rts_sd ) );
  //  to_vector(a_h) ~ normal(0, .5);
  //to_vector(b_h) ~ normal(0, .5);
  S ~ lkj_corr( 1 );

  // likelihood
  if ( distribution == 0 ) {
    for(t in 1:T){
      rts[t,] ~ multi_normal(mu[t,], H[t,]);
    }
  } else if ( distribution == 1 ) {
    for(t in 1:T){
      rts[t,] ~ multi_student_t(nu, mu[t,], H[t,]);
    }
  }
}
generated quantities {
  matrix[nt,T] rts_out;
  real log_lik[T];
  corr_matrix[nt] corH[T];
  // for the no-predictor case
  vector<lower=0>[nt] c_h_var = exp(c_h);
  // retrodict
#include /generated/retrodict_H.stan

}
