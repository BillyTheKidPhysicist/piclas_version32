#include "boltzplatz.h"

MODULE MOD_Equation
!===================================================================================================================================
! Add comments please!
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
INTERFACE InitEquation
  MODULE PROCEDURE InitEquation
END INTERFACE
INTERFACE ExactFunc
  MODULE PROCEDURE ExactFunc 
END INTERFACE
INTERFACE CalcSource
  MODULE PROCEDURE CalcSource
END INTERFACE
INTERFACE DivCleaningDamping
  MODULE PROCEDURE DivCleaningDamping
END INTERFACE

INTERFACE VolInt_Pois
  MODULE PROCEDURE VolInt_weakForm
END INTERFACE

INTERFACE FillFlux_Pois
  MODULE PROCEDURE FillFlux
END INTERFACE

INTERFACE ProlongToFace_Pois
  MODULE PROCEDURE ProlongToFace_sideBased
END INTERFACE

INTERFACE SurfInt_Pois
  MODULE PROCEDURE SurfInt2
END INTERFACE

#ifdef MPI
PUBLIC::StartExchangeMPIData_Pois
#endif
PUBLIC::VolInt_Pois,FillFlux_Pois, ProlongToFace_Pois, SurfInt_Pois
PUBLIC::InitEquation,ExactFunc,CalcSource,FinalizeEquation,DivCleaningDamping,EvalGradient,CalcSource_Pois,DivCleaningDamping_Pois
!===================================================================================================================================

CONTAINS

SUBROUTINE InitEquation()
!===================================================================================================================================
! Get the constant advection velocity vector from the ini file 
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_Mesh_Vars
USE MOD_ReadInTools
USE MOD_Basis,ONLY:PolynomialDerivativeMatrix
USE MOD_Interpolation_Vars, ONLY: xGP
#ifdef PARTICLES
USE MOD_Interpolation_Vars,ONLY:InterpolationInitIsDone
#endif
USE MOD_Equation_Vars 
USE MOD_TimeDisc_Vars, ONLY: TEnd
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                             :: c_test
INTEGER                          :: iBC
#ifdef MPI
#endif

!===================================================================================================================================
! Read the maximum number of time steps MaxIter and the end time TEnd from ini file
TEnd=GetReal('TEnd') ! must be read in here due to DSMC_init
IF(InterpolationInitIsDone.AND.EquationInitIsDone)THEN
   SWRITE(*,*) "InitElectrostatic Poisson not ready to be called or already called."
   RETURN
END IF
SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)') ' INIT ELECTROSTATIC POISSON...'

! Read correction velocity
c_corr             = GETREAL('c_corr','1.')
c                  = GETREAL('c0','1.')
eps0               = GETREAL('eps','1.')
mu0                = GETREAL('mu','1.')
fDamping           = GETREAL('fDamping','0.99')
c_test = 1./SQRT(eps0*mu0)
IF ( ABS(c-c_test)/c.GT.10E-8) THEN
  SWRITE(*,*) "ERROR: c does not equal 1/sqrt(eps*mu)!"
  SWRITE(*,*) "c:", c
  SWRITE(*,*) "mu:", mu0
  SWRITE(*,*) "eps:", eps0
  SWRITE(*,*) "1/sqrt(eps*mu):", c_test
  STOP
END IF
Pi=ACOS(-1.)

c2     = c*c 
c_inv  = 1./c
c2_inv = 1./c2

c_corr2   = c_corr*c_corr
c_corr_c  = c_corr*c 
c_corr_c2 = c_corr*c2
eta_c     = (c_corr-1.)*c

! Read in boundary parameters
IniExactFunc = GETINT('IniExactFunc')
!WRITE(DefBCState,'(I3,A,I3,A,I3,A,I3,A,I3,A,I3)') &
!  IniExactFunc,',',IniExactFunc,',',IniExactFunc,',',IniExactFunc,',',IniExactFunc,',',IniExactFunc
!IF(BCType_in(1) .EQ. -999)THEN
!  BCType = GETINTARRAY('BoundaryType',6)
!ELSE
!  BCType=BCType_in
!  SWRITE(UNIT_stdOut,*)'|                   BoundaryType | -> Already read in CreateMPICart!'
!END IF
!BCState   = GETINTARRAY('BoundaryState',6,TRIM(DefBCState))
!BoundaryCondition(:,1) = BCType
!BoundaryCondition(:,2) = BCState
! Read exponent for shape function
alpha_shape = GETINT('AlphaShape','2')
rCutoff     = GETREAL('r_cutoff','1.')
! Compute factor for shape function
ShapeFuncPrefix = 1/(2 * beta(1.5, alpha_shape + 1.) * alpha_shape + 2 * beta(1.5, alpha_shape + 1.)) &
                * (alpha_shape + 1.)/(PI*(rCutoff**3))

!Init PHI
ALLOCATE(Phi(PP_nVar,0:PP_N,0:PP_N,0:PP_N,PP_nElems))
! the time derivative computed with the DG scheme
ALLOCATE(Phit(PP_nVar,0:PP_N,0:PP_N,0:PP_N,PP_nElems))
nTotalPhi=PP_nVar*(PP_N+1)*(PP_N+1)*(PP_N+1)*PP_nElems

!IF(.NOT.DoRestart)THEN
!  ! U is filled with the ini solution
!  CALL FillIni()
!END IF
! Ut is set to zero because it is successively updated with DG contributions
Phit=0.

! We store the interior data at the each element face
ALLOCATE(Phi_Minus(PP_nVar,0:PP_N,0:PP_N,sideID_minus_lower:sideID_minus_upper))
ALLOCATE(Phi_Plus(PP_nVar,0:PP_N,0:PP_N,sideID_plus_lower:sideID_plus_upper))
Phi_Minus=0.
Phi_Plus=0.

! unique flux per side
ALLOCATE(FluxPhi(PP_nVar,0:PP_N,0:PP_N,1:nSides))
FluxPhi=0.

!ElectricField as grad Phi
ALLOCATE(E(1:3,0:PP_N,0:PP_N,0:PP_N,PP_nElems))

ALLOCATE(D(0:PP_N,0:PP_N))
CALL PolynomialDerivativeMatrix(N,xGP,D)

EquationInitIsDone=.TRUE.
SWRITE(UNIT_stdOut,'(A)')' INIT ELECTROSTATIC POISSON DONE!'
SWRITE(UNIT_StdOut,'(132("-"))')
END SUBROUTINE InitEquation



SUBROUTINE ExactFunc(ExactFunction,t,tDeriv,x,resu) 
!===================================================================================================================================
! Specifies all the initial conditions. The state in conservative variables is returned.
!===================================================================================================================================
! MODULES
USE nr,only:bessj
USE nrtype,only:SP
USE MOD_Globals
USE MOD_Equation_Vars,ONLY:Pi,c,c2,eps0
USE MOD_TimeDisc_vars,ONLY:dt
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)                 :: t
INTEGER,INTENT(IN)              :: tDeriv           ! determines the time derivative of the function
REAL,INTENT(IN)                 :: x(3)              
INTEGER,INTENT(IN)              :: ExactFunction    ! determines the exact function
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)                :: Resu(PP_nVar)    ! state in conservative variables
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
REAL                            :: Resu_t(PP_nVar),Resu_tt(PP_nVar) ! state in conservative variables
REAL                            :: Frequency,Amplitude,Omega
REAL                            :: Cent(3),r,r2,zlen
REAL                            :: a, b, d, l, m, n, B0            ! aux. Variables for Resonator-Example
REAL                            :: gamma,Psi,GradPsiX,GradPsiY     !     -"-
REAL                            :: xrel(3), theta, Etheta          ! aux. Variables for Dipole
REAL,PARAMETER                  :: xDipole(1:3)=(/0,0,0/)          ! aux. Constants for Dipole
REAL,PARAMETER                  :: Q=1, dD=1, omegaD=2.096         ! aux. Constants for Dipole
REAL                            :: c1,s1,b1,b2                     ! aux. Variables for Gyrotron
REAL                            :: eps,phi,z                       ! aux. Variables for Gyrotron
REAL                            :: Er,Br,Ephi,Bphi,Bz              ! aux. Variables for Gyrotron
REAL, PARAMETER                 :: B0G=1.0,g=3236.706462           ! aux. Constants for Gyrotron
REAL, PARAMETER                 :: k0=3562.936537,h=1489.378411    ! aux. Constants for Gyrotron
REAL, PARAMETER                 :: omegaG=3.562936537e+3           ! aux. Constants for Gyrotron
INTEGER, PARAMETER              :: mG=34,nG=19                     ! aux. Constants for Gyrotron
!===================================================================================================================================
Cent=x
SELECT CASE (ExactFunction)
#ifdef PARTICLES
CASE(0) ! Particles
  Resu=0.
  !resu(1:3)= x(1:3)!*x(1) 
#endif
CASE(1) ! Constant 
  Resu=1.
  Resu_t=0.
  Resu_tt=0.

CASE DEFAULT
  SWRITE(*,*)'Exact function not specified'
END SELECT ! ExactFunction

# if (PP_TimeDiscMethod==1)
! For O3 RK, the boundary condition has to be adjusted
! Works only for O3 RK!!
SELECT CASE(tDeriv)
CASE(0)
  ! resu = g(t)
CASE(1)
  ! resu = g(t) + dt/3*g'(t)
  Resu=Resu + dt/3.*Resu_t
CASE DEFAULT
  ! Stop, works only for 3 Stage O3 LS RK
  CALL abort(__STAMP__,'Exactfuntion works only for 3 Stage O3 LS RK!',999,999.)
END SELECT
#endif
END SUBROUTINE ExactFunc



SUBROUTINE CalcSource(t)
!===================================================================================================================================
! Specifies all the initial conditions. The state in conservative variables is returned.
!===================================================================================================================================
! MODULES
USE MOD_Globals,       ONLY : abort
USE MOD_PreProc
USE MOD_DG_Vars,       ONLY : Ut
USE MOD_Equation_Vars, ONLY : eps0,c_corr,IniExactFunc
USE MOD_PICDepo_Vars,  ONLY : Source
USE MOD_Mesh_Vars,     ONLY : Elem_xGP                  ! for shape function: xyz position of the Gauss points
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)                 :: t
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
INTEGER                         :: i,j,k,iElem
REAL                            :: eps0inv
!===================================================================================================================================
eps0inv = 1./eps0
SELECT CASE (IniExactFunc)
CASE(0) ! Particles
  DO iElem=1,PP_nElems
    DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N 
      !  Get source from Particles
      Ut(  4,i,j,k,iElem) = Ut(  4,i,j,k,iElem) + eps0inv * source(  4,i,j,k,iElem) * c_corr 
      !IF((t.GT.0).AND.(ABS(source(4,i,j,k,iElem)*c_corr).EQ.0))THEN
      !print*, t
     ! print*, eps0inv * source(4,i,j,k,iElem)*c_corr
      !print*, eps0inv * source(1:3,i,j,k,iElem)
      !read*
      !END IF
    END DO; END DO; END DO
  END DO
CASE(1) ! Constant          - no sources
CASE DEFAULT
  CALL abort(__STAMP__,'Exactfunction not specified!',999,999.)
END SELECT ! ExactFunction
END SUBROUTINE CalcSource

SUBROUTINE CalcSource_Pois(t)
!===================================================================================================================================
! Specifies all the initial conditions. The state in conservative variables is returned.
!===================================================================================================================================
! MODULES
USE MOD_Globals,       ONLY : abort
USE MOD_PreProc
USE MOD_Equation_Vars, ONLY : Phit
USE MOD_DG_Vars,       ONLY: U
USE MOD_Equation_Vars, ONLY : eps0,c_corr,IniExactFunc
USE MOD_PICDepo_Vars,  ONLY : Source
USE MOD_Mesh_Vars,     ONLY : Elem_xGP                  ! for shape function: xyz position of the Gauss points
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)                 :: t
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
INTEGER                         :: i,j,k,iElem
REAL                            :: eps0inv
!===================================================================================================================================
eps0inv = 1./eps0
SELECT CASE (IniExactFunc)
CASE(0) ! Particles
  DO iElem=1,PP_nElems
    DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N 
      !  Get source from Particles

      Phit(  2:4,i,j,k,iElem) = Phit(  2:4,i,j,k,iElem) - U(  1:3,i,j,k,iElem)*c_corr
      !IF((t.GT.0).AND.(ABS(source(4,i,j,k,iElem)*c_corr).EQ.0))THEN
      !print*, t
     ! print*, eps0inv * source(4,i,j,k,iElem)*c_corr
      !print*, eps0inv * source(1:3,i,j,k,iElem)
      !read*
      !END IF
    END DO; END DO; END DO
  END DO
CASE(1) ! Constant          - no sources
CASE DEFAULT
  CALL abort(__STAMP__,'Exactfunction not specified!',999,999.)
END SELECT ! ExactFunction
END SUBROUTINE CalcSource_Pois

SUBROUTINE DivCleaningDamping()
!===================================================================================================================================
! Specifies all the initial conditions. The state in conservative variables is returned.
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_DG_Vars,       ONLY : U
USE MOD_Equation_Vars, ONLY : fDamping
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
INTEGER                         :: i,j,k,iElem
!===================================================================================================================================
  DO iElem=1,PP_nElems
    DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N 
      !  Get source from Particles
      U(4,i,j,k,iElem) = U(4,i,j,k,iElem) * fDamping
    END DO; END DO; END DO
  END DO
END SUBROUTINE DivCleaningDamping


SUBROUTINE DivCleaningDamping_Pois()
!===================================================================================================================================
! Specifies all the initial conditions. The state in conservative variables is returned.
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_Equation_Vars,       ONLY : Phi
USE MOD_Equation_Vars, ONLY : fDamping
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
INTEGER                         :: i,j,k,iElem
!===================================================================================================================================
  DO iElem=1,PP_nElems
    DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N 
      !  Get source from Particles
      Phi(2:4,i,j,k,iElem) = Phi(2:4,i,j,k,iElem) * fDamping
    END DO; END DO; END DO
  END DO
END SUBROUTINE DivCleaningDamping_Pois

FUNCTION shapefunc(r)
!===================================================================================================================================
! Implementation of (possibly several different) shapefunctions 
!===================================================================================================================================
! MODULES
  USE MOD_Equation_Vars, ONLY : shapeFuncPrefix, alpha_shape, rCutoff
! IMPLICIT VARIABLE HANDLING
    IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
    REAL                 :: r         ! radius / distance to center
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
    REAL                 :: shapefunc ! sort of a weight for the source
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
!===================================================================================================================================
   IF (r.GE.rCutoff) THEN
     shapefunc = 0.0
   ELSE
     shapefunc = ShapeFuncPrefix *(1-(r/rCutoff)**2)**alpha_shape
   END IF
END FUNCTION shapefunc

FUNCTION beta(z,w)                                                                                                
   USE nr
   IMPLICIT NONE
   REAL beta, w, z                                                                                                  
   beta = exp(gammln(z)+gammln(w)-gammln(z+w))                                                                    
END FUNCTION beta 

SUBROUTINE FinalizeEquation()
!===================================================================================================================================
! Get the constant advection velocity vector from the ini file
!===================================================================================================================================
! MODULES
USE MOD_Equation_Vars,ONLY:EquationInitIsDone
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
EquationInitIsDone = .FALSE.
END SUBROUTINE FinalizeEquation



SUBROUTINE EvalGradient()
!===================================================================================================================================
! Computes the gradient of the conservative variables
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
USE MOD_PreProc
USE MOD_Mesh_Vars, ONLY: Metrics_fTilde,Metrics_gTilde,Metrics_hTilde, sJ
USE MOD_Equation_Vars,ONLY:D,E,Phi
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
REAL,DIMENSION(0:PP_N,0:PP_N,0:PP_N)            :: gradPhi_xi,gradPhi_eta,gradPhi_zeta
INTEGER                                :: i,j,k,l,iElem
INTEGER,SAVE                           :: N_old=0
!===================================================================================================================================


DO iElem = 1, PP_nElems
  ! Compute the gradient in the reference system
  gradPhi_xi  = 0.
  gradPhi_eta = 0.
  gradPhi_zeta= 0.
  DO l=0,PP_N
    DO k=0,PP_N
      DO j=0,PP_N
        DO i=0,PP_N
          gradPhi_xi(i,j,k)  = gradPhi_xi(i,j,k)   + D(i,l) * Phi(1,l,j,k,iElem)
          gradPhi_eta(i,j,k) = gradPhi_eta(i,j,k)  + D(j,l) * Phi(1,i,l,k,iElem)
          gradPhi_zeta(i,j,k)= gradPhi_zeta(i,j,k) + D(k,l) * Phi(1,i,j,l,iElem)
       END DO ! i 
     END DO ! j 
    END DO ! k 
  END DO ! l 
  ! Transform the gradients from the reference system to the xyz-System. Only exact for cartesian mesh!
  DO k=0,N
    DO j=0,N
      DO i=0,N
        E(1,i,j,k,iElem) = -1*sJ(i,j,k,iElem) * (                                   &   
                          Metrics_fTilde(1,i,j,k,iElem) * gradPhi_xi(i,j,k)   + & 
                          Metrics_gTilde(1,i,j,k,iElem) * gradPhi_eta(i,j,k)  + & 
                          Metrics_hTilde(1,i,j,k,iElem) * gradPhi_zeta(i,j,k)   )   
        E(2,i,j,k,iElem) = -1*sJ(i,j,k,iElem) * (                                   &   
                          Metrics_fTilde(2,i,j,k,iElem) * gradPhi_xi(i,j,k)   + & 
                          Metrics_gTilde(2,i,j,k,iElem) * gradPhi_eta(i,j,k)  + & 
                          Metrics_hTilde(2,i,j,k,iElem) * gradPhi_zeta(i,j,k)   )   
        E(3,i,j,k,iElem) = -1*sJ(i,j,k,iElem) * (                                   &   
                          Metrics_fTilde(3,i,j,k,iElem) * gradPhi_xi(i,j,k)   + & 
                          Metrics_gTilde(3,i,j,k,iElem) * gradPhi_eta(i,j,k)  + & 
                          Metrics_hTilde(3,i,j,k,iElem) * gradPhi_zeta(i,j,k)   )   
      END DO ! i 
    END DO ! j 
  END DO ! k 
END DO
END SUBROUTINE EvalGradient

SUBROUTINE VolInt_weakForm(Ut)
!===================================================================================================================================
! Computes the volume integral of the weak DG form a la Kopriva
! Attention 1: 1/J(i,j,k) is not yet accounted for
! Attention 2: input Ut=0. and is updated with the volume flux derivatives
!===================================================================================================================================
! MODULES
USE MOD_DG_Vars,ONLY:D_hat
USE MOD_Mesh_Vars,ONLY:Metrics_fTilde,Metrics_gTilde,Metrics_hTilde
USE MOD_PreProc
USE MOD_Flux_Pois,ONLY:EvalFlux3D_Pois                                         ! computes volume fluxes in local coordinates
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(INOUT)                                  :: Ut(PP_nVar,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems)
! Adds volume contribution to time derivative Ut contained in MOD_DG_Vars (=aufschmutzen!)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,DIMENSION(PP_nVar,0:PP_N,0:PP_N,0:PP_N)      :: f,g,h                ! volume fluxes at all Gauss points
REAL,DIMENSION(PP_nVar)                           :: fTilde,gTilde,hTilde ! auxiliary variables needed to store the fluxes at one GP
INTEGER                                           :: i,j,k,iElem
INTEGER                                           :: l                    ! row index for matrix vector product
!===================================================================================================================================
DO iElem=1,PP_nElems
  ! Cut out the local DG solution for a grid cell iElem and all Gauss points from the global field
  ! Compute for all Gauss point values the Cartesian flux components
  CALL EvalFlux3D_Pois(iElem,f,g,h)
  DO k=0,PP_N
    DO j=0,PP_N
      DO i=0,PP_N
        fTilde=f(:,i,j,k)
        gTilde=g(:,i,j,k)
        hTilde=h(:,i,j,k)
        ! Compute the transformed fluxes with the metric terms
        ! Attention 1: we store the transformed fluxes in f,g,h again
        f(:,i,j,k) = fTilde(:)*Metrics_fTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_fTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_fTilde(3,i,j,k,iElem)
        g(:,i,j,k) = fTilde(:)*Metrics_gTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_gTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_gTilde(3,i,j,k,iElem)
        h(:,i,j,k) = fTilde(:)*Metrics_hTilde(1,i,j,k,iElem) + &
                     gTilde(:)*Metrics_hTilde(2,i,j,k,iElem) + &
                     hTilde(:)*Metrics_hTilde(3,i,j,k,iElem)
      END DO ! i
    END DO ! j
  END DO ! k
  DO l=0,PP_N
    DO k=0,PP_N
      DO j=0,PP_N
        DO i=0,PP_N
          ! Update the time derivative with the spatial derivatives of the transformed fluxes
          Ut(:,i,j,k,iElem) = Ut(:,i,j,k,iElem) + D_hat(i,l)*f(:,l,j,k) + &
                                                  D_hat(j,l)*g(:,i,l,k) + &
                                                  D_hat(k,l)*h(:,i,j,l)
        END DO !i
      END DO ! j
    END DO ! k
  END DO ! l
END DO ! iElem
END SUBROUTINE VolInt_weakForm

SUBROUTINE FillFlux(Flux,doMPISides)
!===================================================================================================================================
!
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_Equation_Vars,         ONLY: Phi_Minus,Phi_Plus
USE MOD_Mesh_Vars,       ONLY: NormVec,TangVec1,TangVec2,SurfElem
USE MOD_Mesh_Vars,       ONLY: nSides,nBCSides,nInnerSides,nMPISides_MINE
USE MOD_Riemann_Pois,         ONLY: Riemann_Pois
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
LOGICAL,INTENT(IN) :: doMPISides  != .TRUE. only MINE MPISides are filled, =.FALSE. InnerSides  
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)   :: Flux(1:PP_nVar,0:PP_N,0:PP_N,nSides)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER            :: SideID,p,q,firstSideID,lastSideID
!===================================================================================================================================
! fill flux for sides ranging between firstSideID and lastSideID using Riemann solver
IF(doMPISides)THEN 
  ! fill only flux for MINE MPISides
  firstSideID = nBCSides+nInnerSides+1
  lastSideID  = firstSideID-1+nMPISides_MINE 
ELSE
  ! fill only InnerSides
  firstSideID = nBCSides+1
  lastSideID  = firstSideID-1+nInnerSides 
END IF
!firstSideID=nBCSides+1
!lastSideID  =nBCSides+nInnerSides+nMPISides_MINE
DO SideID=firstSideID,lastSideID
  CALL Riemann_Pois(Flux(:,:,:,SideID),     Phi_Minus(:,:,:,SideID),     Phi_Plus(:,:,:,SideID), &
               NormVec(:,:,:,SideID),TangVec1(:,:,:,SideID),TangVec2(:,:,:,SideID))
  DO q=0,PP_N
    DO p=0,PP_N
      Flux(:,p,q,SideID)=Flux(:,p,q,SideID)*SurfElem(p,q,SideID)
    END DO
  END DO
END DO ! SideID

END SUBROUTINE FillFlux

SUBROUTINE ProlongToFace_SideBased(Uvol,Uface_Minus,Uface_Plus,doMPISides)
!===================================================================================================================================
! Interpolates the interior volume data (stored at the Gauss or Gauss-Lobatto points) to the surface
! integration points, using fast 1D Interpolation and store in global side structure
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Interpolation_Vars, ONLY: L_Minus,L_Plus
USE MOD_PreProc
USE MOD_Mesh_Vars,          ONLY: SideToElem
USE MOD_Mesh_Vars,          ONLY: nSides,nBCSides,nInnerSides,nMPISides_MINE,nMPISides_YOUR
USE MOD_Mesh_Vars,          ONLY: SideID_minus_lower,SideID_minus_upper
USE MOD_Mesh_Vars,          ONLY: SideID_plus_lower,SideID_plus_upper
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
LOGICAL,INTENT(IN)              :: doMPISides  != .TRUE. only YOUR MPISides are filled, =.FALSE. BCSides +InnerSides +MPISides MINE 
REAL,INTENT(IN)                 :: Uvol(4,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(INOUT)              :: Uface_Minus(4,0:PP_N,0:PP_N,sideID_minus_lower:sideID_minus_upper)
REAL,INTENT(INOUT)              :: Uface_Plus(4,0:PP_N,0:PP_N,sideID_plus_lower:sideID_plus_upper)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
INTEGER                         :: i,l,p,q,ElemID(2),SideID,flip(2),LocSideID(2),firstSideID,lastSideID
REAL                            :: Uface(4,0:PP_N,0:PP_N)
!===================================================================================================================================
IF(doMPISides)THEN
  ! only YOUR MPI Sides are filled
  firstSideID = nBCSides+nInnerSides+nMPISides_MINE+1
  lastSideID  = firstSideID-1+nMPISides_YOUR 
  flip(1)      = -1
ELSE
  ! BCSides, InnerSides and MINE MPISides are filled
  firstSideID = 1
  lastSideID  = nBCSides+nInnerSides+nMPISides_MINE
  flip(1)      = 0
END IF
DO SideID=firstSideID,lastSideID
  ! master side, flip=0
  ElemID(1)     = SideToElem(S2E_ELEM_ID,SideID)  
  locSideID(1) = SideToElem(S2E_LOC_SIDE_ID,SideID)
  ! neighbor side !ElemID,locSideID and flip =-1 if not existing
  ElemID(2)     = SideToElem(S2E_NB_ELEM_ID,SideID)
  locSideID(2) = SideToElem(S2E_NB_LOC_SIDE_ID,SideID)
  flip(2)      = SideToElem(S2E_FLIP,SideID)
  DO i=1,2 !first maste then slave side
#if (PP_NodeType==1) /* for Gauss-points*/
    SELECT CASE(locSideID(i))
    CASE(XI_MINUS)
      DO q=0,PP_N
        DO p=0,PP_N
          Uface(:,q,p)=Uvol(:,0,p,q,ElemID(i))*L_Minus(0)
          DO l=1,PP_N
            ! switch to right hand system
            Uface(:,q,p)=Uface(:,q,p)+Uvol(:,l,p,q,ElemID(i))*L_Minus(l)
          END DO ! l
        END DO ! p
      END DO ! q
    CASE(ETA_MINUS)
      DO q=0,PP_N
        DO p=0,PP_N
          Uface(:,p,q)=Uvol(:,p,0,q,ElemID(i))*L_Minus(0)
          DO l=1,PP_N
            Uface(:,p,q)=Uface(:,p,q)+Uvol(:,p,l,q,ElemID(i))*L_Minus(l)
          END DO ! l
        END DO ! p
      END DO ! q
    CASE(ZETA_MINUS)
      DO q=0,PP_N
        DO p=0,PP_N
          Uface(:,q,p)=Uvol(:,p,q,0,ElemID(i))*L_Minus(0)
          DO l=1,PP_N
            ! switch to right hand system
            Uface(:,q,p)=Uface(:,q,p)+Uvol(:,p,q,l,ElemID(i))*L_Minus(l)
          END DO ! l
        END DO ! p
      END DO ! q
    CASE(XI_PLUS)
      DO q=0,PP_N
        DO p=0,PP_N
          Uface(:,p,q)=Uvol(:,0,p,q,ElemID(i))*L_Plus(0)
          DO l=1,PP_N
            Uface(:,p,q)=Uface(:,p,q)+Uvol(:,l,p,q,ElemID(i))*L_Plus(l)
          END DO ! l
        END DO ! p
      END DO ! q
    CASE(ETA_PLUS)
      DO q=0,PP_N
        DO p=0,PP_N
          Uface(:,PP_N-p,q)=Uvol(:,p,0,q,ElemID(i))*L_Plus(0)
          DO l=1,PP_N
            ! switch to right hand system
            Uface(:,PP_N-p,q)=Uface(:,PP_N-p,q)+Uvol(:,p,l,q,ElemID(i))*L_Plus(l)
          END DO ! l
        END DO ! p
      END DO ! q
    CASE(ZETA_PLUS)
      DO q=0,PP_N
        DO p=0,PP_N
          Uface(:,p,q)=Uvol(:,p,q,0,ElemID(i))*L_Plus(0)
          DO l=1,PP_N
            Uface(:,p,q)=Uface(:,p,q)+Uvol(:,p,q,l,ElemID(i))*L_Plus(l)
          END DO ! l
        END DO ! p
      END DO ! q
    END SELECT
#else /* for Gauss-Lobatto-points*/
    SELECT CASE(locSideID(i))
    CASE(XI_MINUS)
      DO q=0,PP_N
        DO p=0,PP_N
          Uface(:,q,p)=Uvol(:,0,p,q,ElemID(i))
        END DO ! p
      END DO ! q
    CASE(ETA_MINUS)
      Uface(:,:,:)=Uvol(:,:,0,:,ElemID(i))
    CASE(ZETA_MINUS)
      DO q=0,PP_N
        DO p=0,PP_N
          Uface(:,q,p)=Uvol(:,p,q,0,ElemID(i))
        END DO ! p
      END DO ! q
    CASE(XI_PLUS)
      Uface(:,:,:)=Uvol(:,PP_N,:,:,ElemID(i))
    CASE(ETA_PLUS)
      DO q=0,PP_N
        DO p=0,PP_N
          Uface(:,PP_N-p,q)=Uvol(:,p,PP_N,q,ElemID(i))
        END DO ! p
      END DO ! q
    CASE(ZETA_PLUS)
      DO q=0,PP_N
        DO p=0,PP_N
          Uface(:,p,q)=Uvol(:,p,q,PP_N,ElemID(i))
        END DO ! p
      END DO ! q
    END SELECT
#endif
    SELECT CASE(Flip(i))
      CASE(0) ! master side
        Uface_Minus(:,:,:,SideID)=Uface(:,:,:)
      CASE(1) ! slave side, SideID=q,jSide=p
        DO q=0,PP_N
          DO p=0,PP_N
            Uface_Plus(:,p,q,SideID)=Uface(:,q,p)
          END DO ! p
        END DO ! q
      CASE(2) ! slave side, SideID=N-p,jSide=q
        DO q=0,PP_N
          DO p=0,PP_N
            Uface_Plus(:,p,q,SideID)=Uface(:,PP_N-p,q)
          END DO ! p
        END DO ! q
      CASE(3) ! slave side, SideID=N-q,jSide=N-p
        DO q=0,PP_N
          DO p=0,PP_N
            Uface_Plus(:,p,q,SideID)=Uface(:,PP_N-q,PP_N-p)
          END DO ! p
        END DO ! q
      CASE(4) ! slave side, SideID=p,jSide=N-q
        DO q=0,PP_N
          DO p=0,PP_N
            Uface_Plus(:,p,q,SideID)=Uface(:,p,PP_N-q)
          END DO ! p
        END DO ! q
    END SELECT
  END DO !i=1,2, masterside & slave side 
END DO !SideID
END SUBROUTINE ProlongToFace_SideBased

#ifdef MPI
SUBROUTINE StartExchangeMPIData_Pois(FaceData,LowerBound,UpperBound,SendRequest,RecRequest,SendID)
!===================================================================================================================================
! Subroutine does the send and receive operations for the face data that has to be exchanged between processors.
! FaceData: the complete face data (for inner, BC and MPI sides).
! LowerBound / UpperBound: lower side index and upper side index for last dimension of FaceData
! SendRequest, RecRequest: communication handles
! SendID: defines the send / receive direction -> 1=send MINE / receive YOUR  2=send YOUR / recieve MINE
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_MPI_Vars
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN)          :: SendID
INTEGER, INTENT(IN)          :: LowerBound,UpperBound
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
INTEGER, INTENT(OUT)         :: SendRequest(nNbProcs),RecRequest(nNbProcs)
REAL, INTENT(INOUT)          :: FaceData(1:4,0:PP_N,0:PP_N,LowerBound:UpperBound)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
DO iNbProc=1,nNbProcs
  ! Start send face data
  IF(nMPISides_send(iNbProc,SendID).GT.0)THEN
    nSendVal    =4*(PP_N+1)*(PP_N+1)*nMPISides_send(iNbProc,SendID)
    SideID_start=OffsetMPISides_send(iNbProc-1,SendID)+1
    SideID_end  =OffsetMPISides_send(iNbProc,SendID)
    CALL MPI_ISEND(FaceData(:,:,:,SideID_start:SideID_end),nSendVal,MPI_DOUBLE_PRECISION,  &
                    nbProc(iNbProc),0,MPI_COMM_WORLD,SendRequest(iNbProc),iError)
  END IF
  ! Start receive face data
  IF(nMPISides_rec(iNbProc,SendID).GT.0)THEN
    nRecVal     =4*(PP_N+1)*(PP_N+1)*nMPISides_rec(iNbProc,SendID)
    SideID_start=OffsetMPISides_rec(iNbProc-1,SendID)+1
    SideID_end  =OffsetMPISides_rec(iNbProc,SendID)
    CALL MPI_IRECV(FaceData(:,:,:,SideID_start:SideID_end),nRecVal,MPI_DOUBLE_PRECISION,  &
                    nbProc(iNbProc),0,MPI_COMM_WORLD,RecRequest(iNbProc),iError)
  END IF
END DO !iProc=1,nNBProcs
END SUBROUTINE StartExchangeMPIData_Pois
#endif

SUBROUTINE SurfInt2(Flux,Ut,doMPISides)
!===================================================================================================================================
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_DG_Vars,            ONLY: L_HatPlus,L_HatMinus
USE MOD_Mesh_Vars,          ONLY: SideToElem
USE MOD_Mesh_Vars,          ONLY: nSides,nBCSides,nInnerSides,nMPISides_MINE,nMPISides_YOUR
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
LOGICAL,INTENT(IN) :: doMPISides  != .TRUE. only YOUR MPISides are filled, =.FALSE. BCSides+InnerSides+MPISides MINE  
REAL,INTENT(IN)    :: Flux(1:4,0:PP_N,0:PP_N,nSides)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(INOUT)   :: Ut(4,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER            :: i,ElemID(2),p,q,l,Flip(2),SideID,locSideID(2)
INTEGER            :: firstSideID,lastSideID
#if (PP_NodeType>1)
REAL            ::L_HatMinus0,L_HatPlusN 
#endif
!===================================================================================================================================
IF(doMPISides)THEN 
  ! surfInt only for YOUR MPISides
  firstSideID = nBCSides+nInnerSides+nMPISides_MINE +1
  lastSideID  = firstSideID-1+nMPISides_YOUR 
ELSE
  ! fill only InnerSides
  firstSideID = 1
  lastSideID  = nBCSides+nInnerSides+nMPISides_MINE
END IF

#if (PP_NodeType>1)
L_HatMinus0 = L_HatMinus(0)
L_HatPlusN  = L_HatPlus(PP_N)
#endif
flip(1)        = 0 !flip=0 for master side
DO SideID=firstSideID,lastSideID
  ! master side, flip=0
  ElemID(1)    = SideToElem(S2E_ELEM_ID,SideID)  
  locSideID(1) = SideToElem(S2E_LOC_SIDE_ID,SideID)
  ! neighbor side
  ElemID(2)    = SideToElem(S2E_NB_ELEM_ID,SideID)
  locSideID(2) = SideToElem(S2E_NB_LOC_SIDE_ID,SideID)
  flip(2)      = SideToElem(S2E_FLIP,SideID)
  
  DO i=1,2
  ! update DG time derivative with corresponding SurfInt contribution
#if (PP_NodeType==1)
    SELECT CASE(locSideID(i))
    CASE(XI_MINUS)
      SELECT CASE(flip(i))
      CASE(0) ! master side
        DO q=0,PP_N; DO p=0,PP_N; DO l=0,PP_N
          Ut(:,l,p,q,ElemID(i))=Ut(:,l,p,q,ElemID(i))+Flux(:,q,p,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! l,p,q
      CASE(1) ! slave side, SideID=q,jSide=p
        DO q=0,PP_N; DO p=0,PP_N; DO l=0,PP_N
          Ut(:,l,p,q,ElemID(i))=Ut(:,l,p,q,ElemID(i))-Flux(:,p,q,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! l,p,q
      CASE(2) ! slave side, SideID=N-p,jSide=q
        DO q=0,PP_N; DO p=0,PP_N; DO l=0,PP_N
          Ut(:,l,p,q,ElemID(i))=Ut(:,l,p,q,ElemID(i))-Flux(:,PP_N-q,p,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! l,p,q
      CASE(3) ! slave side, SideID=N-q,jSide=N-p
        DO q=0,PP_N; DO p=0,PP_N; DO l=0,PP_N
          Ut(:,l,p,q,ElemID(i))=Ut(:,l,p,q,ElemID(i))-Flux(:,PP_N-p,PP_N-q,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! l,p,q
      CASE(4) ! slave side, SideID=p,jSide=N-q
        DO q=0,PP_N; DO p=0,PP_N; DO l=0,PP_N
          Ut(:,l,p,q,ElemID(i))=Ut(:,l,p,q,ElemID(i))-Flux(:,q,PP_N-p,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! l,p,q
      END SELECT

    CASE(ETA_MINUS)
      SELECT CASE(flip(i))
      CASE(0) ! master side
        DO q=0,PP_N; DO l=0,PP_N; DO p=0,PP_N
          Ut(:,p,l,q,ElemID(i))=Ut(:,p,l,q,ElemID(i))+Flux(:,p,q,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! p,l,q
      CASE(1) ! slave side, SideID=q,jSide=p
        DO q=0,PP_N; DO l=0,PP_N; DO p=0,PP_N
          Ut(:,p,l,q,ElemID(i))=Ut(:,p,l,q,ElemID(i))-Flux(:,q,p,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! p,l,q
      CASE(2) ! slave side, SideID=N-p,jSide=q
        DO q=0,PP_N; DO l=0,PP_N; DO p=0,PP_N
          Ut(:,p,l,q,ElemID(i))=Ut(:,p,l,q,ElemID(i))-Flux(:,PP_N-p,q,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! p,l,q
      CASE(3) ! slave side, SideID=N-q,jSide=N-p
        DO q=0,PP_N; DO l=0,PP_N; DO p=0,PP_N
          Ut(:,p,l,q,ElemID(i))=Ut(:,p,l,q,ElemID(i))-Flux(:,PP_N-q,PP_N-p,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! p,l,q
      CASE(4) ! slave side, SideID=p,jSide=N-q
        DO q=0,PP_N; DO l=0,PP_N; DO p=0,PP_N
          Ut(:,p,l,q,ElemID(i))=Ut(:,p,l,q,ElemID(i))-Flux(:,p,PP_N-q,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! p,l,q
      END SELECT
    
    CASE(ZETA_MINUS)
      SELECT CASE(flip(i))
      CASE(0) ! master side
        DO l=0,PP_N; DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,l,ElemID(i))=Ut(:,p,q,l,ElemID(i))+Flux(:,q,p,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! p,q,l
      CASE(1) ! slave side, SideID=q,jSide=p
        DO l=0,PP_N; DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,l,ElemID(i))=Ut(:,p,q,l,ElemID(i))-Flux(:,p,q,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! p,q,l
      CASE(2) ! slave side, SideID=N-p,jSide=q
        DO l=0,PP_N; DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,l,ElemID(i))=Ut(:,p,q,l,ElemID(i))-Flux(:,PP_N-q,p,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! p,q,l
      CASE(3) ! slave side, SideID=N-q,jSide=N-p
        DO l=0,PP_N; DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,l,ElemID(i))=Ut(:,p,q,l,ElemID(i))-Flux(:,PP_N-p,PP_N-q,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! p,q,l
      CASE(4) ! slave side, SideID=p,jSide=N-q
        DO l=0,PP_N; DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,l,ElemID(i))=Ut(:,p,q,l,ElemID(i))-Flux(:,q,PP_N-p,SideID)*L_hatMinus(l)
        END DO; END DO; END DO ! p,q,l
      END SELECT
      
    CASE(XI_PLUS)
      SELECT CASE(flip(i))
      CASE(0) ! master side
        DO q=0,PP_N; DO p=0,PP_N; DO l=0,PP_N
          Ut(:,l,p,q,ElemID(i))=Ut(:,l,p,q,ElemID(i))+Flux(:,p,q,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! l,p,q
      CASE(1) ! slave side, SideID=q,jSide=p
        DO q=0,PP_N; DO p=0,PP_N; DO l=0,PP_N
          Ut(:,l,p,q,ElemID(i))=Ut(:,l,p,q,ElemID(i))-Flux(:,q,p,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! l,p,q
      CASE(2) ! slave side, SideID=N-p,jSide=q
        DO q=0,PP_N; DO p=0,PP_N; DO l=0,PP_N
          Ut(:,l,p,q,ElemID(i))=Ut(:,l,p,q,ElemID(i))-Flux(:,PP_N-p,q,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! l,p,q
      CASE(3) ! slave side, SideID=N-q,jSide=N-p
        DO q=0,PP_N; DO p=0,PP_N; DO l=0,PP_N
          Ut(:,l,p,q,ElemID(i))=Ut(:,l,p,q,ElemID(i))-Flux(:,PP_N-q,PP_N-p,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! l,p,q
      CASE(4) ! slave side, SideID=p,jSide=N-q
        DO q=0,PP_N; DO p=0,PP_N; DO l=0,PP_N
          Ut(:,l,p,q,ElemID(i))=Ut(:,l,p,q,ElemID(i))-Flux(:,p,PP_N-q,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! l,p,q
      END SELECT

    CASE(ETA_PLUS)
      SELECT CASE(flip(i))
      CASE(0) ! master side
        DO q=0,PP_N; DO l=0,PP_N; DO p=0,PP_N
          Ut(:,p,l,q,ElemID(i))=Ut(:,p,l,q,ElemID(i))+Flux(:,PP_N-p,q,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! p,l,q
      CASE(1) ! slave side, SideID=q,jSide=p
        DO q=0,PP_N; DO l=0,PP_N; DO p=0,PP_N
          Ut(:,p,l,q,ElemID(i))=Ut(:,p,l,q,ElemID(i))-Flux(:,q,PP_N-p,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! p,l,q
      CASE(2) ! slave side, SideID=N-p,jSide=q
        DO q=0,PP_N; DO l=0,PP_N; DO p=0,PP_N
          Ut(:,p,l,q,ElemID(i))=Ut(:,p,l,q,ElemID(i))-Flux(:,p,q,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! p,l,q
      CASE(3) ! slave side, SideID=N-q,jSide=N-p
        DO q=0,PP_N; DO l=0,PP_N; DO p=0,PP_N
          Ut(:,p,l,q,ElemID(i))=Ut(:,p,l,q,ElemID(i))-Flux(:,PP_N-q,p,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! p,l,q
      CASE(4) ! slave side, SideID=p,jSide=N-q
        DO q=0,PP_N; DO l=0,PP_N; DO p=0,PP_N
          Ut(:,p,l,q,ElemID(i))=Ut(:,p,l,q,ElemID(i))-Flux(:,PP_N-p,PP_N-q,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! p,l,q
      END SELECT
    
    CASE(ZETA_PLUS)
      SELECT CASE(flip(i))
      CASE(0) ! master side
        DO l=0,PP_N; DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,l,ElemID(i))=Ut(:,p,q,l,ElemID(i))+Flux(:,p,q,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! p,q,l
      CASE(1) ! slave side, SideID=q,jSide=p
        DO l=0,PP_N; DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,l,ElemID(i))=Ut(:,p,q,l,ElemID(i))-Flux(:,q,p,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! p,q,l
      CASE(2) ! slave side, SideID=N-p,jSide=q
        DO l=0,PP_N; DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,l,ElemID(i))=Ut(:,p,q,l,ElemID(i))-Flux(:,PP_N-p,q,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! p,q,l
      CASE(3) ! slave side, SideID=N-q,jSide=N-p
        DO l=0,PP_N; DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,l,ElemID(i))=Ut(:,p,q,l,ElemID(i))-Flux(:,PP_N-q,PP_N-p,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! p,q,l
      CASE(4) ! slave side, SideID=p,jSide=N-q
        DO l=0,PP_N; DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,l,ElemID(i))=Ut(:,p,q,l,ElemID(i))-Flux(:,p,PP_N-q,SideID)*L_hatPlus(l)
        END DO; END DO; END DO ! p,q,l
      END SELECT
    END SELECT !locSideID
#else
    !update local grid cell
    SELECT CASE(locSideID(i))
    CASE(XI_MINUS)
      SELECT CASE(flip(i))
      CASE(0)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,0,p,q,ElemID(i))=Ut(:,0,p,q,ElemID(i))+Flux(:,q,p,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(1)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,0,p,q,ElemID(i))=Ut(:,0,p,q,ElemID(i))-Flux(:,p,q,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(2)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,0,p,q,ElemID(i))=Ut(:,0,p,q,ElemID(i))-Flux(:,PP_N-q,p,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(3)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,0,p,q,ElemID(i))=Ut(:,0,p,q,ElemID(i))-Flux(:,PP_N-p,PP_N-q,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(4)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,0,p,q,ElemID(i))=Ut(:,0,p,q,ElemID(i))-Flux(:,q,PP_N-p,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      END SELECT
    
    ! switch to right hand system for ETA_PLUS direction
    CASE(ETA_MINUS)
      SELECT CASE(flip(i))
      CASE(0)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,0,q,ElemID(i))=Ut(:,p,0,q,ElemID(i))+Flux(:,p,q,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(1)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,0,q,ElemID(i))=Ut(:,p,0,q,ElemID(i))-Flux(:,q,p,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(2)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,0,q,ElemID(i))=Ut(:,p,0,q,ElemID(i))-Flux(:,PP_N-p,q,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(3)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,0,q,ElemID(i))=Ut(:,p,0,q,ElemID(i))-Flux(:,PP_N-q,PP_N-p,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(4)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,0,q,ElemID(i))=Ut(:,p,0,q,ElemID(i))-Flux(:,p,PP_N-q,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      END SELECT
    
    ! switch to right hand system for ZETA_MINUS direction
    CASE(ZETA_MINUS)
      SELECT CASE(flip(i))
      CASE(0)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,0,ElemID(i))=Ut(:,p,q,0,ElemID(i))+Flux(:,q,p,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(1)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,0,ElemID(i))=Ut(:,p,q,0,ElemID(i))-Flux(:,p,q,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(2)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,0,ElemID(i))=Ut(:,p,q,0,ElemID(i))-Flux(:,PP_N-q,p,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(3)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,0,ElemID(i))=Ut(:,p,q,0,ElemID(i))-Flux(:,PP_N-p,PP_N-q,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      CASE(4)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,0,ElemID(i))=Ut(:,p,q,0,ElemID(i))-Flux(:,q,PP_N-p,SideID)*L_hatMinus0
        END DO; END DO ! p,q
      END SELECT
    
    CASE(XI_PLUS)
      SELECT CASE(flip(i))
      CASE(0)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,PP_N,p,q,ElemID(i))=Ut(:,PP_N,p,q,ElemID(i))+Flux(:,p,q,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(1)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,PP_N,p,q,ElemID(i))=Ut(:,PP_N,p,q,ElemID(i))-Flux(:,q,p,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(2)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,PP_N,p,q,ElemID(i))=Ut(:,PP_N,p,q,ElemID(i))-Flux(:,PP_N-p,q,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(3)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,PP_N,p,q,ElemID(i))=Ut(:,PP_N,p,q,ElemID(i))-Flux(:,PP_N-q,PP_N-p,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(4)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,PP_N,p,q,ElemID(i))=Ut(:,PP_N,p,q,ElemID(i))-Flux(:,p,PP_N-q,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      END SELECT
    
    ! switch to right hand system for ETA_PLUS direction
    CASE(ETA_PLUS)
      SELECT CASE(flip(i))
      CASE(0)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,PP_N,q,ElemID(i))=Ut(:,p,PP_N,q,ElemID(i))+Flux(:,PP_N-p,q,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(1)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,PP_N,q,ElemID(i))=Ut(:,p,PP_N,q,ElemID(i))-Flux(:,q,PP_N-p,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(2)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,PP_N,q,ElemID(i))=Ut(:,p,PP_N,q,ElemID(i))-Flux(:,p,q,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(3)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,PP_N,q,ElemID(i))=Ut(:,p,PP_N,q,ElemID(i))-Flux(:,PP_N-q,p,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(4)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,PP_N,q,ElemID(i))=Ut(:,p,PP_N,q,ElemID(i))-Flux(:,PP_N-p,PP_N-q,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      END SELECT

    ! switch to right hand system for ZETA_MINUS direction
    CASE(ZETA_PLUS)
      SELECT CASE(flip(i))
      CASE(0)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,PP_N,ElemID(i))=Ut(:,p,q,PP_N,ElemID(i))+Flux(:,p,q,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(1)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,PP_N,ElemID(i))=Ut(:,p,q,PP_N,ElemID(i))-Flux(:,q,p,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(2)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,PP_N,ElemID(i))=Ut(:,p,q,PP_N,ElemID(i))-Flux(:,PP_N-p,q,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(3)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,PP_N,ElemID(i))=Ut(:,p,q,PP_N,ElemID(i))-Flux(:,PP_N-q,PP_N-p,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      CASE(4)
        DO q=0,PP_N; DO p=0,PP_N
          Ut(:,p,q,PP_N,ElemID(i))=Ut(:,p,q,PP_N,ElemID(i))-Flux(:,p,PP_N-q,SideID)*L_hatPlusN
        END DO; END DO ! p,q
      END SELECT
    END SELECT !locSideID
#endif
  END DO ! i=1,2 master side, slave side
END DO ! SideID=1,nSides
END SUBROUTINE SurfInt2

END MODULE MOD_Equation
