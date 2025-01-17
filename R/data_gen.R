packages <- c("data.table","tidyverse","skimr","here","foreach","doParallel","doRNG","boot","survival","ggplot2")

for (package in packages) {
  if (!require(package, character.only=T, quietly=T)) {
    install.packages(package, repos='http://lib.stat.cmu.edu/R/CRAN')
  }
}

for (package in packages) {
  library(package, character.only=T)
}

thm <- theme_classic() +
  theme(
    legend.position = "top",
    legend.background = element_rect(fill = "transparent", colour = NA),
    legend.key = element_rect(fill = "transparent", colour = NA)
  )
theme_set(thm)

set.seed(123)

expit <- function(x){1/(1 + exp(-x))}

n<-5000 #Number of subjects

N<-12 #number of intervals per subject

K<-1 # Number of causes of death

## This is the matrix of parameters of interest, possibly different
## at each interval

psi.mat<-matrix(0,nrow=K,ncol=N+1)

##Here are the effect sizes for the K=2 causes

psi.mat[1,]<-- -log(2.5)
#psi.mat[2,]<-- log(4.5)

##Here the (untreated) all-cause rate is set to lambda=0.01, with
##lambda/K per cause; muK=lambda is used in the algorithm.

lambda<-0.0375
gamma.vec<-rep(log(lambda/K))
muK<-sum(exp(gamma.vec))
A<-L<-ID<-Y<-Z<-Tv<-Int<-ALast<-LLast<-LFirst<-numeric()
T0.vec<-T.vec<-Y.vec<-Z.vec<-rep(0,n)

##Here are the coefficients determining the
##mediation and treatment assignment mechanisms.
bevec<-c(log(3/7),log(2),log(.5),log(2))
alvec<-c(log(2/7),log(2),log(2),log(2))
##Begin the data-generation loop
for(i in 1:n){
  ##Generate the counterfactual (untreated) survival time
  T0<-rexp(1,lambda)
  Ival<-as.numeric(T0 < 15) # median T0 introduces confounding
  ##Begin the interval-by-interval simulation
  m<-0
  mu.tot<-0
  A.vec<-L.vec<-ALast.vec<-LLast.vec<-LFirst.vec<-rep(0,N+1)
  ##Implement Young's algorithm with multiple causes
  ##Generate the survival time, then the cause
  while(muK*T0 > mu.tot & m <= N){
    if(m == 0){
      ##First interval
      eta<-bevec[1]+bevec[2]*Ival+bevec[3]*0+bevec[4]*0
      pval<-1/(1+exp(-eta))
      L.vec[m+1]<-rbinom(1,1,pval)
      eta<-alvec[1]+alvec[2]*L.vec[m+1]+alvec[3]*0+alvec[4]*0
      pval<-1/(1+exp(-eta))
      A.vec[m+1]<-rbinom(1,1,pval)
      ALast.vec[m+1]<-0;LLast.vec[m+1]<-0
      LFirst.vec<-rep(L.vec[m+1],N+1)
    }else{
      ##Subsequent intervals
      eta<-bevec[1]+bevec[2]*Ival+bevec[3]*A.vec[m]+bevec[4]*L.vec[m]
      pval<-1/(1+exp(-eta))
      L.vec[m+1]<-rbinom(1,1,pval)
      eta<-alvec[1]+alvec[2]*L.vec[m+1]+alvec[3]*L.vec[m]+alvec[4]*A.vec[m]
      pval<-1/(1+exp(-eta))
      A.vec[m+1]<-rbinom(1,1,pval)
      ALast.vec[m+1]<-A.vec[m];LLast.vec[m+1]<-L.vec[m]
    }
    muval<-sum(exp(gamma.vec+A.vec[m+1]*psi.mat[,m+1]))
    ##Tval is computed for each interval, but is overwritten
    ##until the final interval
    Tval<-m+(muK*T0-mu.tot)/muval
    mu.tot<-mu.tot+muval
    m<-m+1
  }
  ##After exiting the loop, the survival time has been generated as Tval
  ##Now need to generate the failure type.
  if(m > N){
    ##In the case of censoring at tenth interval, no failure.
    Tval<-m-1
    Z.vec[i]<-0
  }else{
    ##In the case of failure, use the ratio hazards to define the
    ##relevant multinomial distribution on the K causes.
    Z.vec[i]<-sample(c(1:K),1,prob=exp(gamma.vec+A.vec[m]*psi.mat[,m]))
  }
  ##Store the outcomes
  T0.vec[i]<-T0
  T.vec[i]<-Tval
  Y.vec[i]<-m-1
  T0.v <- c(T0.vec,c(1:m))
  ID<-c(ID,rep(i,m))
  Int<-c(Int,c(1:m))
  A<-c(A,A.vec[1:m])
  L<-c(L,L.vec[1:m])
  ALast<-c(ALast,ALast.vec[1:m])
  LLast<-c(LLast,LLast.vec[1:m])
  LFirst<-c(LFirst,LFirst.vec[1:m])
  Z<-c(Z,rep(0,m-1),Z.vec[i])
  tv<-c(1:m);tv[m]<-Tval
  Tv<-c(Tv,tv)
}
PO.dat <- data.frame(ID=1:5000,T0.vec)
D<-data.frame(ID,Int,Tv,A,ALast,L,LLast,Z)
D <- left_join(D,PO.dat)
##Trim off the intervals beyond the Nth (loop goes one too far)
D<-D[D$Int<=N,]
names(D)<-c("ID","int","time","X","Xm1","Z","Zm1","Y","T0")
D$timem1<-D$int-1
D$last_flag<-as.numeric(D$Y!=0|D$time==N)

hist(D[D$last_flag==1,]$T0)
mean(as.numeric(D[D$last_flag==1,]$T0<15))
print(aggregate(D$Y,list(D$int),mean))
print(aggregate(D$X,list(D$int),mean))

# generate mis-measured X
## need to think of independent and nondifferential, dependent and nondifferential
## independent and differential, and dependent and differential errors
## See Hernan and Cole (2009) Causal Diagrams and Measurement Bias

D$X_prime <- rbinom(nrow(D),1,expit(-log(1/.36 - 1) - log(2)*.36 + log(2)*D$X  ))

print(aggregate(D$X_prime,list(D$int),mean))

table(D$X,D$X_prime)

## Gabriel, let's talk about all the scenarios we could explore above

write_csv(D,here("data/example_dat.csv"))
