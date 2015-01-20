#include "boltzplatz.h"

MODULE MOD_DSMC_CollisionProb
!===================================================================================================================================
! Module calculating the collision probability
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

INTERFACE DSMC_prob_calc
  MODULE PROCEDURE DSMC_prob_calc
END INTERFACE

!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
PUBLIC :: DSMC_prob_calc
!===================================================================================================================================

CONTAINS

SUBROUTINE DSMC_prob_calc(iElem, iPair, NodeVolume)
!===================================================================================================================================
! Routine calculating the collision probability
!===================================================================================================================================
! MODULES
  USE MOD_Globals
  USE MOD_DSMC_Vars,              ONLY : SpecDSMC, Coll_pData, CollInf, DSMC, BGGas, ChemReac
  USE MOD_Particle_Vars,          ONLY : PartSpecies, Species, GEO, usevMPF
!  USE MOD_Particle_Vars,          ONLY : PartState       ! da muss noch was getan werden (s.u.)
  USE MOD_TimeDisc_Vars,          ONLY : dt
!  USE MOD_Equation_Vars,          ONLY : c2              ! da muss noch was getan werden (s.u.)
  USE MOD_DSMC_SpecXSec
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
  INTEGER, INTENT(IN)                 :: iElem, iPair
  REAL(KIND=8), INTENT(IN), OPTIONAL  :: NodeVolume
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  INTEGER                             :: iPType, SpecToExec, NbrOfReaction
  INTEGER(KIND=8)                     :: SpecNum1, SpecNum2
  REAL                                :: aCEX, bCEX, aMEX, bMEX, BGGasDensity_new
  REAL(KIND=8)                        :: Volume
!===================================================================================================================================
  
  iPType = SpecDSMC(PartSpecies(Coll_pData(iPair)%iPart_p1))%InterID &
         + SpecDSMC(PartSpecies(Coll_pData(iPair)%iPart_p2))%InterID !definition of collision case

  IF (PRESENT(NodeVolume)) THEN
    Volume = NodeVolume
  ELSE
    Volume = GEO%Volume(iElem)
  END IF
  SELECT CASE(iPType)

    CASE(2,3,4,11) !Atom-Atom,  Atom-Mol, Mol-Mol, non-CEX/MEX Atom-Atomic Ion
      SpecNum1 = CollInf%Coll_SpecPartNum(PartSpecies(Coll_pData(iPair)%iPart_p1)) !number of particles of spec 1
      SpecNum2 = CollInf%Coll_SpecPartNum(PartSpecies(Coll_pData(iPair)%iPart_p2)) !number of particles of spec 2
      IF (BGGas%BGGasSpecies.NE.0) THEN       
        Coll_pData(iPair)%Prob = BGGas%BGColl_SpecPartNum/(1 + CollInf%KronDelta(Coll_pData(iPair)%PairType))  & 
                * CollInf%Cab(Coll_pData(iPair)%PairType)                                               & ! Cab species comb fac
                * Species(PartSpecies(Coll_pData(iPair)%iPart_p1))%MacroParticleFactor                  & 
                        ! weighting Fact, here only one MPF is used!!!
                * Coll_pData(iPair)%CRela2 ** (0.5-SpecDSMC(PartSpecies(Coll_pData(iPair)%iPart_p1))%omegaVHS) &
                        ! relative velo to the power of (1 -2omega) !! only one omega is used!!
                * dt / Volume                     ! timestep (should be sclaed in time disc)  divided by cell volume
      ELSE
        Coll_pData(iPair)%Prob = SpecNum1*SpecNum2/(1 + CollInf%KronDelta(Coll_pData(iPair)%PairType))  & 
                * CollInf%Cab(Coll_pData(iPair)%PairType)                                               & ! Cab species comb fac
                * Species(PartSpecies(Coll_pData(iPair)%iPart_p1))%MacroParticleFactor                  & 
                        ! weighting Fact, here only one MPF is used!!!
                / CollInf%Coll_CaseNum(Coll_pData(iPair)%PairType)                                      & ! sum of coll cases Sab
                * Coll_pData(iPair)%CRela2 ** (0.5-SpecDSMC(PartSpecies(Coll_pData(iPair)%iPart_p1))%omegaVHS) &
                        ! relative velo to the power of (1 -2omega) !! only one omega is used!!
                * dt / Volume                     ! timestep (should be sclaed in time disc)  divided by cell volume
      END IF

    CASE(5) !Atom - Electron ! Molecule - Electron
      ALLOCATE(Coll_pData(iPair)%Sigma(0:3))  ! Cross Section of Collision of this pair
      Coll_pData(iPair)%Sigma = 0
! ist/war gedacht als relativistische energie, da elektronen ja doch recht schnell werden ...
!prob ist, dass hier nicht die gesamte Ec sonder nur die SchwerpunktsEc gebracuht wird.
! hier muß also für relativistische Fälle noch etwas getan werden
!      Ec = 0 ! Energy of collision (in case of e + A = Ekin)
!      
!      !relativistic Ekin of particle 1
!      partV2 = PartState(Coll_pData(iPair)%iPart_p1,4) * PartState(Coll_pData(iPair)%iPart_p1,4) &
!               + PartState(Coll_pData(iPair)%iPart_p1,5) * PartState(Coll_pData(iPair)%iPart_p1,5) &
!               + PartState(Coll_pData(iPair)%iPart_p1,6) * PartState(Coll_pData(iPair)%iPart_p1,6)
!      GammaRel = partV2/c2
!      GammaRel = 1./SQRT(1.-GammaRel)  !Calculation of the Lorenzt Boost of the particle
!      Ec = Ec + (GammaRel-1.) &
!           * Species(PartSpecies(Coll_pData(iPair)%iPart_p1))%MassIC &
!           * Species(PartSpecies(Coll_pData(iPair)%iPart_p1))%MacroParticleFactor * c2 ! Only to use with one MPF!!
!      
!      !relativistic Ekin of particle 2
!      partV2 = PartState(Coll_pData(iPair)%iPart_p2,4) * PartState(Coll_pData(iPair)%iPart_p2,4) &
!               + PartState(Coll_pData(iPair)%iPart_p2,5) * PartState(Coll_pData(iPair)%iPart_p2,5) &
!               + PartState(Coll_pData(iPair)%iPart_p2,6) * PartState(Coll_pData(iPair)%iPart_p2,6)
!      GammaRel = partV2/c2
!      GammaRel = 1./SQRT(1.-GammaRel)  !Calculation of the Lorenzt Boost of the particle
!      Ec = Ec + (GammaRel-1.) &
!           * Species(PartSpecies(Coll_pData(iPair)%iPart_p2))%MassIC &
!           * Species(PartSpecies(Coll_pData(iPair)%iPart_p2))%MacroParticleFactor * c2 ! Only to use with one MPF!!
!      Coll_pData(iPair)%Ec = Ec
      Coll_pData(iPair)%Ec = 0.5 * CollInf%MassRed(Coll_pData(iPair)%PairType)*Coll_pData(iPair)%CRela2
  
      ! Define what spezies is the atom and is execuded
    !!!!!!!!DEBUG
      IF (SpecDSMC(PartSpecies(Coll_pData(iPair)%iPart_p1))%InterID.eq.1) THEN
        SpecToExec = PartSpecies(Coll_pData(iPair)%iPart_p1) 
      ELSE
        SpecToExec = PartSpecies(Coll_pData(iPair)%iPart_p2)
      END IF
      SELECT CASE(SpecDSMC(SpecToExec)%NumOfPro)        ! Number of protons, which element
        CASE (18)                                      ! Argon
          CALL XSec_Argon_DravinLotz(SpecToExec, iPair)
        CASE DEFAULT
          CALL Abort(&
               __STAMP__,&
              'Error: spec proton not defined!',iPType)
      END SELECT
    !!!!!!!!DEBUG

      SpecNum1 = CollInf%Coll_SpecPartNum(PartSpecies(Coll_pData(iPair)%iPart_p1)) !number of particles of spec 1
      SpecNum2 = CollInf%Coll_SpecPartNum(PartSpecies(Coll_pData(iPair)%iPart_p2)) !number of particles of spec 2
      ! generally this is only a HS calculation of the prob
      IF (BGGas%BGGasSpecies.NE.0) THEN
        IF (usevMPF) THEN
          BGGasDensity_new=BGGas%BGGasDensity
          Coll_pData(iPair)%Prob = BGGasDensity_new * GEO%Volume(iElem)      &
                 /(1 + CollInf%KronDelta(Coll_pData(iPair)%PairType))  & 
                        ! weighting Fact, here only one MPF is used!!!      
                * SQRT(Coll_pData(iPair)%CRela2)*Coll_pData(iPair)%Sigma(0) &
                        ! relative velo to the power of (1 -2omega) !! only one omega is used!!
                * dt / Volume                     ! timestep (should be sclaed in time disc)  divided by cell volume
        ELSE
          Coll_pData(iPair)%Prob = BGGas%BGColl_SpecPartNum/(1 + CollInf%KronDelta(Coll_pData(iPair)%PairType))  & 
                * Species(PartSpecies(Coll_pData(iPair)%iPart_p1))%MacroParticleFactor                  & 
                        ! weighting Fact, here only one MPF is used!!!      
                * SQRT(Coll_pData(iPair)%CRela2)*Coll_pData(iPair)%Sigma(0) &
                        ! relative velo to the power of (1 -2omega) !! only one omega is used!!
                * dt / Volume                     ! timestep (should be sclaed in time disc)  divided by cell vol
        END IF
      ELSE
        Coll_pData(iPair)%Prob = SpecNum1*SpecNum2/(1 + CollInf%KronDelta(Coll_pData(iPair)%PairType))  & 
                * Species(PartSpecies(Coll_pData(iPair)%iPart_p1))%MacroParticleFactor                  & 
                        ! weighting Fact, here only one MPF is used!!!      
                / CollInf%Coll_CaseNum(Coll_pData(iPair)%PairType)                                      & ! sum of coll cases Sab
                * SQRT(Coll_pData(iPair)%CRela2)*Coll_pData(iPair)%Sigma(0) &
                        ! relative velo to the power of (1 -2omega) !! only one omega is used!!
                * dt / Volume                     ! timestep (should be sclaed in time disc)  divided by cell volume
      END IF
    CASE(8) !Electron - Electron
      Coll_pData(iPair)%Prob = 0
    CASE(14) !Electron - Atomic Ion
      Coll_pData(iPair)%Prob = 0
    CASE(16) !Atom-Atomic CEX/MEX Ion
      NbrOfReaction = ChemReac%ReactNum(PartSpecies(Coll_pData(iPair)%iPart_p1),PartSpecies(Coll_pData(iPair)%iPart_p2),1)
      aCEX = ChemReac%CEXa(NbrOfReaction)
      bCEX = ChemReac%CEXb(NbrOfReaction)
      aMEX = ChemReac%MEXa(NbrOfReaction)
      bMEX = ChemReac%MEXb(NbrOfReaction)
      SpecNum1 = CollInf%Coll_SpecPartNum(PartSpecies(Coll_pData(iPair)%iPart_p1)) !number of particles of spec 1
      SpecNum2 = CollInf%Coll_SpecPartNum(PartSpecies(Coll_pData(iPair)%iPart_p2)) !number of particles of spec 2
      IF (Coll_pData(iPair)%CRela2.eq.0.) THEN !avoid log(0)
        Coll_pData(iPair)%Prob=0.
      ELSE
        IF (BGGas%BGGasSpecies.NE.0) THEN
          Coll_pData(iPair)%Prob = BGGas%BGColl_SpecPartNum/(1 + CollInf%KronDelta(Coll_pData(iPair)%PairType))  &
            !* CollInf%Cab(Coll_pData(iPair)%PairType)                                               & ! Cab species comb fac
            * Species(PartSpecies(Coll_pData(iPair)%iPart_p1))%MacroParticleFactor                  &
              ! weighting Fact, here only one MPF is used!!!
            * 1.0E-20 * SQRT(Coll_pData(iPair)%CRela2) * ((aCEX+aMEX)*0.5*LOG10(Coll_pData(iPair)%CRela2) + bCEX+bMEX) &
              ! CEX/MEX-relation to relative velo
            * dt / Volume                   ! timestep (should be sclaed in time disc)  divided by cell volume
        ELSE
          Coll_pData(iPair)%Prob = SpecNum1*SpecNum2/(1 + CollInf%KronDelta(Coll_pData(iPair)%PairType))  &
            !* CollInf%Cab(Coll_pData(iPair)%PairType)                                               & ! Cab species comb fac
            * Species(PartSpecies(Coll_pData(iPair)%iPart_p1))%MacroParticleFactor                  &
              ! weighting Fact, here only one MPF is used!!!
            / CollInf%Coll_CaseNum(Coll_pData(iPair)%PairType)                                      & ! sum of coll cases Sab
            * 1.0E-20 * SQRT(Coll_pData(iPair)%CRela2) * ((aCEX+aMEX)*0.5*LOG10(Coll_pData(iPair)%CRela2) + bCEX+bMEX) &
              ! CEX/MEX-relation to relative velo
            * dt / Volume                   ! timestep (should be sclaed in time disc)  divided by cell volume
        END IF
      END IF !avoid log(0)
    CASE(19) !Electron - Atomic CEX/MEX Ion
      Coll_pData(iPair)%Prob = 0
    CASE(20) !Atomic Ion - Atomic Ion
      Coll_pData(iPair)%Prob = 0
    CASE DEFAULT
      CALL Abort(&
           __STAMP__,&
          'ERROR in DSMC_collis: Wrong iPType case! = ',iPType)
  END SELECT
  IF (ISNAN(Coll_pData(iPair)%Prob)) THEN
    IPWRITE(*,*)iPair,'in',iElem,'is NaN!'
    CALL Abort(&
         __STAMP__,&
        'Collision probability is NaN! CRela:',RealInfoOpt=SQRT(Coll_pData(iPair)%CRela2))
  END IF
  DSMC%CollProbOut(iElem,1) = MAX(Coll_pData(iPair)%Prob, DSMC%CollProbOut(iElem,1))
  DSMC%CollMean = DSMC%CollMean + Coll_pData(iPair)%Prob
  DSMC%CollMeanCount = DSMC%CollMeanCount + 1
END SUBROUTINE DSMC_prob_calc

END MODULE MOD_DSMC_CollisionProb
