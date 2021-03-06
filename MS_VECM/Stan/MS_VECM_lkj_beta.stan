data {
int<lower=1> T; // Number of observations
matrix[T,2] y; // Observations, first difference
matrix[T,2] y_z; // Observations
int<lower=1> ARdim; // Number of AR terms
int<lower=1> nreg; // Number of regimes
int<lower = 0, upper = 1> mean_reg;
int<lower = 0, upper = 1> sigma_reg;
vector[nreg] Q_alpha; // Transition probabilities hyperparameter
real mu_mean; // Mean value of the normal prior for the constant means
real mu_sd; // Standard deviation of the normal prior for the constant means
real phi_mean; // Mean value of the normal prior for the autoregressive coefficients
real phi_sd; // Standard deviation of the normal prior for the autoregressive coefficients
real alpha_mean; // Mean value of the normal prior for the correction coefficients
real alpha_sd; // Standard deviation of the normal prior for the correction coefficients
real eta; // LKJ hyperparameter
real gamma_alpha; // Inverse gamma hyperparameter (shape)
real gamma_beta;  // Inverse gamma hyperparameter (scale)
}

parameters {
simplex[nreg] Q[nreg] ;  // Transition probabilities
vector[2] mu[mean_reg ? nreg : 1]; // Mean
matrix[2,2*ARdim] phi[mean_reg ? nreg : 1]; // AR coefficients
vector[2] alpha[mean_reg ? nreg : 1]; // Correction coefficients
real beta; // Cointegration relationship 

vector<lower=0>[2] vari[sigma_reg ? nreg : 1]; // Variance
cholesky_factor_corr[2] L_corr[sigma_reg ? nreg : 1]; //Lower Cholesky factors of the correlation matrices
}

transformed parameters{
vector[2] sdev[sigma_reg ? nreg : 1];
matrix[2,2] L_sigma[sigma_reg ? nreg : 1];

for(i in 1:(sigma_reg ? nreg : 1)){
	for(j in 1:2){
		sdev[i,j]=sqrt(vari[i,j]);
	}
	L_sigma[i] = diag_pre_multiply(sdev[i], L_corr[i]);
}
}

model {
// Priors

for (k in 1:nreg){
	Q[k] ~ dirichlet(Q_alpha);
}

for (k in 1:(mean_reg ? nreg : 1)){
	mu[k] ~ normal(mu_mean,mu_sd);
	to_vector(phi[k]) ~ normal(phi_mean,phi_sd);	
	alpha[k] ~ normal(alpha_mean,alpha_sd);
}

for (k in 1:(sigma_reg ? nreg : 1)){
	vari[k] ~ inv_gamma(gamma_alpha, gamma_beta);
	L_corr[k] ~ lkj_corr_cholesky(eta);
}
{
    //forward algorithm for computing log p(y|...)
    
	real fwd[nreg,nreg];
    real alphas[T-ARdim,nreg];
	real py[nreg];
	real logQ[nreg,nreg];
	int n_m = mean_reg ? nreg : 1;
	int n_s = sigma_reg ? nreg : 1;
	vector[2] meanval[n_m];
	row_vector[2*ARdim] ylags;
	
	for(i in 1:nreg){
		for (j in 1:nreg){
			logQ[i,j]= log(Q[i,j]);
		}
	}
	
	for(i in 1:ARdim){
		ylags[(i-1)*2+1:i*2]=y[ARdim+1-i,];
	}
	for(k in 1:n_m){
		meanval[k]=mu[k]+phi[k]*ylags'+alpha[k]*(y_z[1,1] - beta*y_z[1,2]);
	} 
	
	for(i in 1:nreg){	
		int ii = i; //added by jbb for min fix
		alphas[1,i] = multi_normal_cholesky_lpdf(y[ARdim+1,] | meanval[min(n_m,ii)],L_sigma[min(n_s,ii)]);
	}
	
    for (t in (ARdim+2):T){	

		for(i in 1:ARdim){
			ylags[(i-1)*2+1:i*2]=y[t-i,];
		}
		for(k in 1:n_m){
			meanval[k]=mu[k]+phi[k]*ylags'+alpha[k]*(y_z[t-1,1] - beta*y_z[t-1,2]);
		}
		
		for(i in 1:nreg){		
			int ii = i; //added by jbb for min fix
			py[i] = multi_normal_cholesky_lpdf(y[t,] | meanval[min(n_m,ii)],L_sigma[min(n_s,ii)]);
		}	
		
		for(i in 1:nreg){
		  for (j in 1:nreg){
			fwd[i,j] = alphas[t-ARdim-1,j] + logQ[i,j] + py[i];
		}
		  alphas[t-ARdim,i]=log_sum_exp(fwd[i,]);
		}
		  
    }
	
	// adding the marginal log-likelihood to Stan target distribution
	
    target += log_sum_exp(alphas[T-ARdim,]);	
}
}

generated quantities {
	matrix[2,2] sigma[sigma_reg ? nreg : 1];
	int<lower=1,upper=2> S[T-ARdim];
	real log_p_S;
  
	for(i in 1:(sigma_reg ? nreg : 1)){
		sigma[i]= multiply_lower_tri_self_transpose(L_sigma[i]);
	}
	
   // Viterbi algorithm 
  { 
    int back_ptr[T-ARdim,nreg];
    real best_logp[T-ARdim+1,nreg];
    real best_total_logp;
	real py[nreg];
	real logQ[nreg,nreg];
	int n_m = mean_reg ? nreg : 1;
	int n_s = sigma_reg ? nreg : 1;
	vector[2] meanval[n_m];
	row_vector[2*ARdim] ylags;
    
    for(i in 1:nreg){
	best_logp[1,i]=0;
	}
	
	for(i in 1:nreg){
		for (j in 1:nreg){
			logQ[i,j]= log(Q[i,j]);
	}
	}
	
    for (t in (ARdim+1):T) {
	
		for(i in 1:ARdim){
			ylags[(i-1)*2+1:i*2]=y[t-i,];
		}
		for(k in 1:n_m){
			meanval[k]=mu[k]+phi[k]*ylags'+alpha[k]*(y_z[t-1,1] - beta*y_z[t-1,2]);
		}
			  	  
	    for(i in 1:nreg){
		  int ii = i; //added by jbb for min fix
		  py[i] = multi_normal_cholesky_lpdf(y[t,] | meanval[min(n_m,ii)],L_sigma[min(n_s,ii)]);
		  best_logp[t-ARdim+1,i] = negative_infinity();
	    }	
	  
        for (j in 1:nreg) {
			real logp[nreg];

			for(k in 1:nreg){	
				logp[k] = best_logp[t-ARdim,j] + logQ[j,k] + py[k];
					
				if (logp[k] > best_logp[t-ARdim+1,k]){
					back_ptr[t-ARdim,k] = j;
					best_logp[t-ARdim+1,k] = logp[k];
				}	
			}
        }
    }
	
    log_p_S = max(best_logp[T-ARdim+1]);
    for (k in 1:nreg){
      if (best_logp[T-ARdim+1,k] == log_p_S){
        S[T-ARdim] = k;
	  }
	}
    for (t in 1:(T - ARdim-1)){
      S[T-ARdim-t] = back_ptr[T-ARdim-t+1, S[T-ARdim-t+1]];
	}
  }
}
