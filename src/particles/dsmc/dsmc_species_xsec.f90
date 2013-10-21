MODULE MOD_DSMC_SpecXSec
!===================================================================================================================================
! Contains the DSMC variables
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PUBLIC

!===================================================================================================================================

CONTAINS

SUBROUTINE XSec_Argon_DravinLotz(SpecToExec, iPair)

  USE MOD_DSMC_Vars,              ONLY : Coll_pData, SpecDSMC
  USE MOD_Equation_Vars,          ONLY : Pi, eps0

!--------------------------------------------------------------------------------------------------!
! collision probability calculation 
!--------------------------------------------------------------------------------------------------!
   IMPLICIT NONE                                                                                   !
!--------------------------------------------------------------------------------------------------!
! argument list declaration                                                                        !
! Local variable declaration                                                                     !

! input variable declaration                                                                       !
INTEGER, INTENT(IN)           :: SpecToExec, iPair
REAL                          :: JToEv, BohrRad, ElemCharge, Rydberg
!--------------------------------------------------------------------------------------------------!
JToEv = 1.602176565E-19 
BohrRad = 0.5291772109E-10
ElemCharge = 1.602176565E-19
Rydberg = 13.60569253*JToEv

!.... Elastic scattering cross section
  Coll_pData(iPair)%Sigma(1) = SQRT(0.5*Pi*SpecDSMC(SpecToExec)%RelPolarizability &
                             * BohrRad**3*ElemCharge**2     &   ! AIAA07 Paper
                             / (eps0*Coll_pData(iPair)%Ec))                    ! units checked

!.... Ionization cross section (Lotz)
IF ((Coll_pData(iPair)%Ec/JToEv).GE.SpecDSMC(SpecToExec)%Eion_eV) THEN
  Coll_pData(iPair)%Sigma(2) = 2.78*SpecDSMC(SpecToExec)%NumEquivElecOutShell*Pi &
             * BohrRad**2*Rydberg**2 &    ! units checked
             / (Coll_pData(iPair)%Ec*SpecDSMC(SpecToExec)%Eion_eV*JToEv) &
             * LOG(Coll_pData(iPair)%Ec/(JToEv*SpecDSMC(SpecToExec)%Eion_eV))
ELSE
  Coll_pData(iPair)%Sigma(2) = 0.0
ENDIF
Coll_pData(iPair)%Sigma(0)=Coll_pData(iPair)%Sigma(1)+Coll_pData(iPair)%Sigma(2) ! Calc of Sigma total
END SUBROUTINE XSec_Argon_DravinLotz

END MODULE MOD_DSMC_SpecXSec
