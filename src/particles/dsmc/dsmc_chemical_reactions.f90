#include "boltzplatz.h"

MODULE MOD_DSMC_ChemReact
!===================================================================================================================================
! module including collisions
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

INTERFACE ElecImpactIoni
  MODULE PROCEDURE ElecImpactIoni
END INTERFACE

INTERFACE SetMeanVibQua
  MODULE PROCEDURE SetMeanVibQua
END INTERFACE

INTERFACE MolecDissoc
  MODULE PROCEDURE MolecDissoc
END INTERFACE

INTERFACE MolecExch
  MODULE PROCEDURE MolecExch
END INTERFACE

INTERFACE AtomRecomb
  MODULE PROCEDURE AtomRecomb
END INTERFACE

INTERFACE simpleCEX
  MODULE PROCEDURE simpleCEX
END INTERFACE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
PUBLIC :: ElecImpactIoni, SetMeanVibQua, MolecDissoc, MolecExch, AtomRecomb, simpleCEX
!===================================================================================================================================

CONTAINS

SUBROUTINE ElecImpactIoni(iReac, iPair)
!===================================================================================================================================
! Perfoms the electron impact ionization
!===================================================================================================================================
! MODULES
USE MOD_DSMC_Vars,             ONLY : Coll_pData, DSMC_RHS, CollInf, SpecDSMC, DSMCSumOfFormedParticles
USE MOD_DSMC_Vars,             ONLY : ChemReac, PartStateIntEn
USE MOD_Particle_Vars,         ONLY : BoltzmannConst, PartSpecies, PartState, PDM, PEM, NumRanVec, RandomVec
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES                                                                                
  INTEGER, INTENT(IN)           :: iPair, iReac
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  REAL                          :: FracMassCent1, FracMassCent2     ! mx/(mx+my)
  REAL                          :: VeloMx, VeloMy, VeloMz           ! center of mass velo
  REAL                          :: RanVelox, RanVeloy, RanVeloz     ! random relativ velo
  INTEGER                       :: iVec
  REAL                          :: JToEv, iRan, FacEtraDistri
  REAL                          :: ERel_React1_React2, ERel_React2_Elec
  INTEGER                       :: PositionNbr, React1Inx, ElecInx
  REAL                          :: VxPseuAtom, VyPseuAtom, VzPseuAtom
!  REAL                           :: FakXi, Xi_rel
!  INTEGER                        :: iQuaMax, iQua, MaxColQua
!===================================================================================================================================

JToEv = 1.602176565E-19

!..Get the index of react1 and the electron
  IF (SpecDSMC(PartSpecies(Coll_pData(iPair)%iPart_p1))%InterID.eq.4) THEN
    ElecInx = Coll_pData(iPair)%iPart_p1
    React1Inx = Coll_pData(iPair)%iPart_p2 
  ELSE
    React1Inx = Coll_pData(iPair)%iPart_p1
    ElecInx = Coll_pData(iPair)%iPart_p2
  END IF

Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - SpecDSMC(PartSpecies(React1Inx))%Eion_eV*JToEv 

!spectoexec muss evtl noch geändert werden, ist ja kein spec sondern ein partikel
!page 31 diss laux DOF

! ! first, the internal energies relax if SpecToExec is a molecule
! IF(molekül) THEN
! ! Vibrational Relaxation if molec
!   Xi_rel = 2*(2 - SpecDSMC(PartSpecies(SpecToExec))%omegaVHS) ! DOF of relative motion in VHS model, only for one omega!!
!           ! this is a result of the mean value of the relative energy in the vhs model, laux diss page 31
!   FakXi = 0.5*(Xi_rel + SpecDSMC(PartSpecies(SpecToExec))%Xi_Rot) - 1
!           ! exponent factor of DOF, substitute of Xi_c - Xi_vib, laux diss page 40
!   MaxColQua = Coll_pData(iPair)%Ec/(BoltzmannConst*SpecDSMC(PartSpecies(SpecToExec))%CharaTVib)  - DSMC%GammaQuant
!   iQuaMax = MIN(INT(MaxColQua) + 1, SpecDSMC(PartSpecies(SpecToExec))%MaxVibQuant)
!   CALL RANDOM_NUMBER(iRan)
!   iQua = INT(iRan * iQuaMax)
!   CALL RANDOM_NUMBER(iRan)
!   DO WHILE (iRan.GT.(1 - iQua/MaxColQua)**FakXi) 
!     !GammaQuant was added, laux diss page 31, this was not in eq in LasVegas
!     CALL RANDOM_NUMBER(iRan)
!     iQua = INT(iRan * iQuaMax)    
!     CALL RANDOM_NUMBER(iRan)
!   END DO
! !spectoexec_evib muss noch genau definiert werden!!!!!!!!!!!!!!
!    spectoexec_evib = (iQua + DSMC%GammaQuant) * BoltzmannConst * SpecDSMC(PartSpecies(SpecToExec))%CharaTVib 
!    Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - spectoexec_evib 

! ! Rotational Relaxation if molec
! !spectoexec_erot muss noch genau definiert werden!!!!!!!!!!!!!!
!    CALL RANDOM_NUMBER(iRan)
!    spectoexec_erot = Coll_pData(iPair)%Ec * (1 - iRan**(1/FakXi))
!    Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - spectoexec_erot 
! END IF
  
  ! distribute Etra of pseudo neutral particle (i+e) and old electron
  CALL RANDOM_NUMBER(iRan)
  FacEtraDistri = iRan
  CALL RANDOM_NUMBER(iRan)
  ! laux diss page 40, omegaVHS only of one species
  DO WHILE ((4 *FacEtraDistri*(1-FacEtraDistri))**(1-SpecDSMC(PartSpecies(React1Inx))%omegaVHS).LT.iRan)
    CALL RANDOM_NUMBER(iRan)
    FacEtraDistri = iRan
    CALL RANDOM_NUMBER(iRan)
  END DO
  ERel_React1_React2 = Coll_pData(iPair)%Ec * FacEtraDistri
  ERel_React2_Elec = Coll_pData(iPair)%Ec - ERel_React1_React2

  !.... Get free particle index for the 3rd particle produced
  DSMCSumOfFormedParticles = DSMCSumOfFormedParticles + 1
  PositionNbr = PDM%nextFreePosition(DSMCSumOfFormedParticles+PDM%CurrentNextFreePosition)
  IF (PositionNbr.EQ.0) THEN
    PRINT*, 'New Particle Number greater max Part Num'
    STOP
  END IF

  !Set new Species of electron
  PDM%ParticleInside(PositionNbr) = .true.
  PartSpecies(PositionNbr) = ChemReac%DefinedReact(iReac,2,2)
  PartState(PositionNbr,1:3) = PartState(React1Inx,1:3)
  PartStateIntEn(PositionNbr, 1) = 0
  PartStateIntEn(PositionNbr, 2) = 0
  PEM%Element(PositionNbr) = PEM%Element(React1Inx)

  !Scattering of pseudo atom (e-i) and collision partner e (scattering of e)
  FracMassCent1 = CollInf%FracMassCent(PartSpecies(React1Inx), Coll_pData(iPair)%PairType)
  FracMassCent2 = CollInf%FracMassCent(PartSpecies(ElecInx), Coll_pData(iPair)%PairType)

  !Calculation of velo from center of mass
  VeloMx = FracMassCent1 * PartState(React1Inx, 4) &
         + FracMassCent2 * PartState(ElecInx, 4)
  VeloMy = FracMassCent1 * PartState(React1Inx, 5) &
         + FracMassCent2 * PartState(ElecInx, 5)
  VeloMz = FracMassCent1 * PartState(React1Inx, 6) &
         + FracMassCent2 * PartState(ElecInx, 6)

  !calculate random vec and new squared velocities
  Coll_pData(iPair)%CRela2 = 2 * ERel_React1_React2 /CollInf%MassRed(Coll_pData(iPair)%PairType)
  CALL RANDOM_NUMBER(iRan)
  iVec = INT(NumRanVec * iRan + 1)
  RanVelox = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,1)
  RanVeloy = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,2)
  RanVeloz = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,3)
  
 ! deltaV particle 2
  DSMC_RHS(ElecInx,1) = VeloMx - FracMassCent1*RanVelox - PartState(ElecInx, 4)
  DSMC_RHS(ElecInx,2) = VeloMy - FracMassCent1*RanVeloy - PartState(ElecInx, 5)
  DSMC_RHS(ElecInx,3) = VeloMz - FracMassCent1*RanVeloz - PartState(ElecInx, 6)
  
  !Set velocity of pseudo atom (i+e)
  VxPseuAtom = VeloMx + FracMassCent2*RanVelox  
  VyPseuAtom = VeloMy + FracMassCent2*RanVeloy 
  VzPseuAtom = VeloMz + FracMassCent2*RanVeloz 

  !Set new Species of formed ion
  PartSpecies(React1Inx) = ChemReac%DefinedReact(iReac,2,1)

  !Scattering of i + e
  FracMassCent1 = CollInf%FracMassCent(PartSpecies(React1Inx), &
                &  CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(PositionNbr)))
  FracMassCent2 = CollInf%FracMassCent(PartSpecies(PositionNbr), & 
                &  CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(PositionNbr)))

  !calculate random vec and new squared velocities
  Coll_pData(iPair)%CRela2 = 2 *  ERel_React2_Elec / & 
          CollInf%MassRed(CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(PositionNbr)))
  CALL RANDOM_NUMBER(iRan)
  iVec = INT(NumRanVec * iRan + 1)
  RanVelox = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,1)
  RanVeloy = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,2)
  RanVeloz = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,3)

  !deltaV particle 1
  DSMC_RHS(React1Inx,1) = VxPseuAtom + FracMassCent2*RanVelox - PartState(React1Inx, 4)
  DSMC_RHS(React1Inx,2) = VyPseuAtom + FracMassCent2*RanVeloy - PartState(React1Inx, 5)
  DSMC_RHS(React1Inx,3) = VzPseuAtom + FracMassCent2*RanVeloz - PartState(React1Inx, 6)
  
  !deltaV new formed particle
  PartState(PositionNbr,4:6) = 0
  DSMC_RHS(PositionNbr,1) = VxPseuAtom - FracMassCent1*RanVelox 
  DSMC_RHS(PositionNbr,2) = VyPseuAtom - FracMassCent1*RanVeloy 
  DSMC_RHS(PositionNbr,3) = VzPseuAtom - FracMassCent1*RanVeloz 

END SUBROUTINE ElecImpactIoni


SUBROUTINE MolecDissoc(iReac, iPair)
!===================================================================================================================================
! Perfom the molecular dissociation
!===================================================================================================================================
! MODULES
USE MOD_Globals,               ONLY : abort
USE MOD_DSMC_Vars,             ONLY : Coll_pData, DSMC_RHS, DSMC, CollInf, SpecDSMC, DSMCSumOfFormedParticles
USE MOD_DSMC_Vars,             ONLY : ChemReac, PartStateIntEn
USE MOD_Particle_Vars,         ONLY : BoltzmannConst, PartSpecies, PartState, PDM, PEM, NumRanVec
USE MOD_Particle_Vars,         ONLY : usevMPF, PartMPF, RandomVec, GEO, Species
USE MOD_vmpf_collision,        ONLY : vMPF_AfterSplitting
USE MOD_DSMC_ElectronicModel,  ONLY : ElectronicEnergyExchange
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES                                                                                
  INTEGER, INTENT(IN)           :: iPair, iReac
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  REAL                          :: FracMassCent1, FracMassCent2     ! mx/(mx+my)
  REAL                          :: VeloMx, VeloMy, VeloMz           ! center of mass velo
  REAL                          :: RanVelox, RanVeloy, RanVeloz     ! random relativ velo
  INTEGER                       :: iVec
  REAL                          :: JToEv, FakXi, Xi_rel, iRan, FacEtraDistri
  REAL                          :: ERel_React1_React2, ERel_React1_React3
  INTEGER                       :: iQuaMax, iQua, PositionNbr, React1Inx, React2Inx, NonReacPart
  REAL                          :: MaxColQua
  REAL                          :: VxPseuMolec, VyPseuMolec, VzPseuMolec
  REAL                          :: DeltaPartStateIntEn, PartStateIntEnTemp, Phi, ReacMPF
  REAL                          :: ElecTransfer
!===================================================================================================================================

JToEv = 1.602176565E-19
ElecTransfer = 0.

!..Get the index of react1 and the react2
  IF (PartSpecies(Coll_pData(iPair)%iPart_p1).EQ.ChemReac%DefinedReact(iReac,1,1)) THEN
    React1Inx = Coll_pData(iPair)%iPart_p1
    React2Inx = Coll_pData(iPair)%iPart_p2 
  ELSE
    React2Inx = Coll_pData(iPair)%iPart_p1
    React1Inx = Coll_pData(iPair)%iPart_p2
  END IF
  IF (usevMPF) THEN ! reaction MPF definition
    ReacMPF = MIN(PartMPF(React1Inx), PartMPF(React2Inx))
    IF (PartMPF(React1Inx).GT.ReacMPF) THEN ! just a part of the molecule diss
    !.... Get free particle index for the non-reacting particle part
      DSMCSumOfFormedParticles = DSMCSumOfFormedParticles + 1
      NonReacPart = PDM%nextFreePosition(DSMCSumOfFormedParticles+PDM%CurrentNextFreePosition)
      IF (NonReacPart.EQ.0) THEN
        CALL abort(&
       __STAMP__&
        ,'New Particle Number greater max Part Num in MolecDiss. Reaction: ',iReac)
      END IF
    ! Copy molecule data for non-reacting particle part
      PDM%ParticleInside(NonReacPart) = .true.
      PartSpecies(NonReacPart)        = PartSpecies(React1Inx)
      PartState(NonReacPart,1:6)      = PartState(React1Inx,1:6)
      PartStateIntEn(NonReacPart, 1)  = PartStateIntEn(React1Inx, 1)
      PartStateIntEn(NonReacPart, 2)  = PartStateIntEn(React1Inx, 2)
      IF (DSMC%ElectronicState) THEN
        PartStateIntEn(NonReacPart, 3)  = PartStateIntEn(React1Inx, 3)
      END IF
      PEM%Element(NonReacPart)        = PEM%Element(React1Inx)
      PartMPF(NonReacPart)            = PartMPF(React1Inx) - ReacMPF ! MPF of non-reacting particle part = MPF Diff
      PartMPF(React1Inx)              = ReacMPF ! reacting part MPF = ReacMPF
    END IF
  END IF
  
  ! Add heat of formation to collision energy
  Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec + ChemReac%EForm(iReac)

  Xi_rel = 4*(2 - SpecDSMC(PartSpecies(Coll_pData(iPair)%iPart_p1))%omegaVHS) 
    ! DOF of relative motion in VHS model, only for one omega!!
    ! this is a result of the mean value of the relative energy in the vhs model, laux diss page 31
  FakXi = 0.5*(Xi_rel + SpecDSMC(PartSpecies(React2Inx))%Xi_Rot) - 1  

   ! check if electronic model is used
  IF ( DSMC%ElectronicState ) THEN
    ! add electronic energy to collision energy
    Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec + PartStateIntEn(React1Inx,3) + &
                                                  PartStateIntEn(React2Inx,3)
    IF (SpecDSMC(PartSpecies(React2Inx))%InterID.EQ.2) THEN
      Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - &
            DSMC%GammaQuant *BoltzmannConst*SpecDSMC(PartSpecies(React2Inx))%CharaTVib 
    END IF
    IF (SpecDSMC(PartSpecies(React2Inx))%InterID.NE.4) THEN
      CALL ElectronicEnergyExchange(Coll_pData(iPair)%Ec,React2Inx,FakXi,React1Inx,PEM%Element(React1Inx))
      ! store the electronic energy of the dissociating molecule
      CALL ElectronicEnergyExchange(Coll_pData(iPair)%Ec,React1Inx,FakXi,React2Inx,PEM%Element(React2Inx))
      ElecTransfer = PartStateIntEn(React1Inx,3)
    END IF
    IF (SpecDSMC(PartSpecies(React2Inx))%InterID.EQ.2) THEN
      Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec + &
            DSMC%GammaQuant *BoltzmannConst*SpecDSMC(PartSpecies(React2Inx))%CharaTVib 
    END IF
  END IF

  IF (SpecDSMC(PartSpecies(React2Inx))%InterID.EQ.2) THEN
    MaxColQua = Coll_pData(iPair)%Ec/(BoltzmannConst*SpecDSMC(PartSpecies(React2Inx))%CharaTVib)  &
              - DSMC%GammaQuant
    iQuaMax = MIN(INT(MaxColQua) + 1, SpecDSMC(PartSpecies(React2Inx))%MaxVibQuant)
    CALL RANDOM_NUMBER(iRan)
    iQua = INT(iRan * iQuaMax)
    CALL RANDOM_NUMBER(iRan)
    DO WHILE (iRan.GT.(1 - iQua/MaxColQua)**FakXi) 
     !laux diss page 31
     CALL RANDOM_NUMBER(iRan)
     iQua = INT(iRan * iQuaMax)    
     CALL RANDOM_NUMBER(iRan)
    END DO
    IF (usevMPF) THEN
      IF (PartMPF(React2Inx).GT.ReacMPF) THEN
      !Vibrational Relaxation of React2Inx
        DeltaPartStateIntEn = 0.0
        Phi = ReacMPF / PartMPF(React2Inx)
        PartStateIntEnTemp = (iQua + DSMC%GammaQuant) * BoltzmannConst &
                      * SpecDSMC(PartSpecies(React2Inx))%CharaTVib
        Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - PartStateIntEnTemp
        PartStateIntEnTemp = (1-Phi) * PartStateIntEn(React2Inx,1) + Phi * PartStateIntEnTemp
        ! searche for new vib quant
        MaxColQua = PartStateIntEnTemp/(BoltzmannConst*SpecDSMC(PartSpecies(React2Inx))%CharaTVib)  &
                  - DSMC%GammaQuant
        iQuaMax = MIN(INT(MaxColQua) + 1, SpecDSMC(PartSpecies(React2Inx))%MaxVibQuant)
        CALL RANDOM_NUMBER(iRan)
        iQua = INT(iRan * iQuaMax)
        CALL RANDOM_NUMBER(iRan)
        DO WHILE (iRan.GT.(1 - iQua/MaxColQua)**FakXi)
         !laux diss page 31
         CALL RANDOM_NUMBER(iRan)
         iQua = INT(iRan * iQuaMax)
         CALL RANDOM_NUMBER(iRan)
        END DO
        PartStateIntEn(React2Inx,1) = (iQua + DSMC%GammaQuant) * BoltzmannConst &
                      * SpecDSMC(PartSpecies(React2Inx))%CharaTVib
        DeltaPartStateIntEn = PartMPF(React2Inx) &
                            * (PartStateIntEnTemp - PartStateIntEn(React2Inx,1))
  
      !Rotational Relaxation of React2Inx
        CALL RANDOM_NUMBER(iRan)
        PartStateIntEnTemp = Coll_pData(iPair)%Ec * (1.0 - iRan**(1.0/FakXi))
        Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - PartStateIntEnTemp
        PartStateIntEn(React2Inx,2) = (1-Phi) * PartStateIntEn(React2Inx,2) &
                                                     + Phi * PartStateIntEnTemp
      ! adding in-energy lost due to vMPF
        Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec + DeltaPartStateIntEn / ReacMPF
      END IF
    ELSE ! no vMPF or MPF of React2Inx .eq. ReacMPF
    !Vibrational Relaxation of React2Inx
      PartStateIntEn(React2Inx,1) = (iQua + DSMC%GammaQuant) * BoltzmannConst &
                    * SpecDSMC(PartSpecies(React2Inx))%CharaTVib
      Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - PartStateIntEn(React2Inx,1)
    !Rotational Relaxation of React2Inx
      CALL RANDOM_NUMBER(iRan)
      PartStateIntEn(React2Inx,2) = Coll_pData(iPair)%Ec * (1.0 - iRan**(1.0/FakXi))
      Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - PartStateIntEn(React2Inx,2) 
    END IF ! (usevMPF).AND.(PartMPF(React2Inx).GT.ReacMPF)
  END IF

  ! distribute Etra of pseudo neutral particle (i+e) and old electron
  CALL RANDOM_NUMBER(iRan)
  FacEtraDistri = iRan
  CALL RANDOM_NUMBER(iRan)
  ! laux diss page 40, omegaVHS only of one species
  DO WHILE ((4 *FacEtraDistri*(1-FacEtraDistri))**(1-SpecDSMC(PartSpecies(React1Inx))%omegaVHS).LT.iRan)
    CALL RANDOM_NUMBER(iRan)
    FacEtraDistri = iRan
    CALL RANDOM_NUMBER(iRan)
  END DO
  ERel_React1_React2 = Coll_pData(iPair)%Ec * FacEtraDistri
  ERel_React1_React3 = Coll_pData(iPair)%Ec - ERel_React1_React2

  !.... Get free particle index for the 3rd particle produced
  DSMCSumOfFormedParticles = DSMCSumOfFormedParticles + 1
  PositionNbr = PDM%nextFreePosition(DSMCSumOfFormedParticles+PDM%CurrentNextFreePosition)
  IF (PositionNbr.EQ.0) THEN
    CALL abort(__STAMP__,&
    'New Particle Number greater max Part Num in MolecDiss. Reaction: ',iReac)
  END IF

  !Set new Species of new atom
  PDM%ParticleInside(PositionNbr) = .true.
  PartSpecies(PositionNbr) = ChemReac%DefinedReact(iReac,2,2)
  PartState(PositionNbr,1:3) = PartState(React1Inx,1:3)
  PartStateIntEn(PositionNbr, 1) = 0
  PartStateIntEn(PositionNbr, 2) = 0
  PEM%Element(PositionNbr) = PEM%Element(React1Inx)
  IF(usevMPF) PartMPF(PositionNbr) = ReacMPF

  !Scattering of pseudo molecule (a-b) and collision partner e (scattering of e)
  FracMassCent1 = CollInf%FracMassCent(PartSpecies(React1Inx), Coll_pData(iPair)%PairType)
  FracMassCent2 = CollInf%FracMassCent(PartSpecies(React2Inx), Coll_pData(iPair)%PairType)

  !Calculation of velo from center of mass
  VeloMx = FracMassCent1 * PartState(React1Inx, 4) &
         + FracMassCent2 * PartState(React2Inx, 4)
  VeloMy = FracMassCent1 * PartState(React1Inx, 5) &
         + FracMassCent2 * PartState(React2Inx, 5)
  VeloMz = FracMassCent1 * PartState(React1Inx, 6) &
         + FracMassCent2 * PartState(React2Inx, 6)

  !calculate random vec and new squared velocities
  Coll_pData(iPair)%CRela2 = 2 * ERel_React1_React2 /CollInf%MassRed(Coll_pData(iPair)%PairType)
  CALL RANDOM_NUMBER(iRan)
  iVec = INT(NumRanVec * iRan + 1)
  RanVelox = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,1)
  RanVeloy = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,2)
  RanVeloz = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,3)
  
 ! deltaV particle 2
  DSMC_RHS(React2Inx,1) = VeloMx - FracMassCent1*RanVelox - PartState(React2Inx, 4)
  DSMC_RHS(React2Inx,2) = VeloMy - FracMassCent1*RanVeloy - PartState(React2Inx, 5)
  DSMC_RHS(React2Inx,3) = VeloMz - FracMassCent1*RanVeloz - PartState(React2Inx, 6)  
  IF (usevMPF) THEN
    IF (PartMPF(React2Inx).GT.ReacMPF) THEN
      Phi = ReacMPF / PartMPF(React2Inx)
      GEO%DeltaEvMPF(PEM%Element(React2Inx)) = GEO%DeltaEvMPF(PEM%Element(React2Inx)) + 0.5 * PartMPF(React2Inx) &
                                             * Species(PartSpecies(React2Inx))%MassIC &
                                             * Phi * (1 - Phi) &
                                             * ( DSMC_RHS(React2Inx,1)**2 &
                                               + DSMC_RHS(React2Inx,2)**2 &
                                               + DSMC_RHS(React2Inx,3)**2 ) 
      DSMC_RHS(React2Inx,1) = Phi * DSMC_RHS(React2Inx,1)
      DSMC_RHS(React2Inx,2) = Phi * DSMC_RHS(React2Inx,2)
      DSMC_RHS(React2Inx,3) = Phi * DSMC_RHS(React2Inx,3) 
    END IF
  END IF

  !Set velocity of pseudo molec (a+b) and calculate the centre of mass frame velocity: m_pseu / (m_3 + m_4) * v_pseu
  !(Velocity of pseudo molecule is NOT equal to the COM frame velocity)
  VxPseuMolec = (VeloMx + FracMassCent2*RanVelox) * Species(PartSpecies(React1Inx))%MassIC &
                  / (Species(ChemReac%DefinedReact(iReac,2,1))%MassIC+Species(ChemReac%DefinedReact(iReac,2,2))%MassIC)
  VyPseuMolec = (VeloMy + FracMassCent2*RanVeloy) * Species(PartSpecies(React1Inx))%MassIC &
                  / (Species(ChemReac%DefinedReact(iReac,2,1))%MassIC+Species(ChemReac%DefinedReact(iReac,2,2))%MassIC)
  VzPseuMolec = (VeloMz + FracMassCent2*RanVeloz) * Species(PartSpecies(React1Inx))%MassIC &
                  / (Species(ChemReac%DefinedReact(iReac,2,1))%MassIC+Species(ChemReac%DefinedReact(iReac,2,2))%MassIC)

  !Set new Species of dissoc atom
  PartSpecies(React1Inx) = ChemReac%DefinedReact(iReac,2,1)

  ! here set the electronic level of the 2 atoms
  IF ( DSMC%ElectronicState ) THEN
    Coll_pData(iPair)%Ec = ElecTransfer + ERel_React1_React3
    CALL ElectronicEnergyExchange(Coll_pData(iPair)%Ec, React1Inx   , FakXi, PositionNbr,PEM%Element(React1Inx) )
    CALL ElectronicEnergyExchange(Coll_pData(iPair)%Ec, PositionNbr , FakXi, React1Inx,PEM%Element(PositionNbr) )
    ERel_React1_React3 = Coll_pData(iPair)%Ec
  END IF

  !Scattering of a + b
  FracMassCent1 = CollInf%FracMassCent(PartSpecies(React1Inx), &
                  CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(PositionNbr)))
  FracMassCent2 = CollInf%FracMassCent(PartSpecies(PositionNbr), & 
                  CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(PositionNbr)))

  !calculate random vec and new squared velocities
  Coll_pData(iPair)%CRela2 = 2 *  ERel_React1_React3 / & 
          CollInf%MassRed(CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(PositionNbr)))
  CALL RANDOM_NUMBER(iRan)
  iVec = INT(NumRanVec * iRan + 1)
  RanVelox = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,1)
  RanVeloy = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,2)
  RanVeloz = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,3)

  !deltaV particle 1
  !PartState(React1Inx,4:6) = 0
  DSMC_RHS(React1Inx,1) = VxPseuMolec + FracMassCent2*RanVelox - PartState(React1Inx, 4)
  DSMC_RHS(React1Inx,2) = VyPseuMolec + FracMassCent2*RanVeloy - PartState(React1Inx, 5)
  DSMC_RHS(React1Inx,3) = VzPseuMolec + FracMassCent2*RanVeloz - PartState(React1Inx, 6)
  !print*,'reactinx1', DSMC_RHS(React1Inx,:)
  PartStateIntEn(React1Inx, 1) = 0
  PartStateIntEn(React1Inx, 2) = 0
  
  !deltaV new formed particle
  PartState(PositionNbr,4:6) = 0
  DSMC_RHS(PositionNbr,1) = VxPseuMolec - FracMassCent1*RanVelox 
  DSMC_RHS(PositionNbr,2) = VyPseuMolec - FracMassCent1*RanVeloy 
  DSMC_RHS(PositionNbr,3) = VzPseuMolec - FracMassCent1*RanVeloz 

  IF(usevMPF) THEN
    IF (ReacMPF.GT.(Species(PartSpecies(React1Inx))%MacroParticleFactor)) THEN
      CALL vMPF_AfterSplitting(React1Inx, ReacMPF, Species(PartSpecies(React1Inx))%MacroParticleFactor)
    END IF
  END IF
  IF(usevMPF) THEN
    IF (ReacMPF.GT.(Species(PartSpecies(PositionNbr))%MacroParticleFactor)) THEN
      CALL vMPF_AfterSplitting(PositionNbr, ReacMPF, Species(PartSpecies(PositionNbr))%MacroParticleFactor)
    END IF
  END IF

END SUBROUTINE MolecDissoc


SUBROUTINE MolecExch(iReac, iPair)
!===================================================================================================================================
! Perform molecular exchange reaction
!===================================================================================================================================
! MODULES
USE MOD_Globals,               ONLY : abort
USE MOD_DSMC_Vars,             ONLY : Coll_pData, DSMC_RHS, DSMC, CollInf, SpecDSMC, DSMCSumOfFormedParticles
USE MOD_DSMC_Vars,             ONLY : ChemReac, PartStateIntEn
USE MOD_Particle_Vars,         ONLY : BoltzmannConst, PartSpecies, PartState, PDM, PEM, NumRanVec, RandomVec
USE MOD_vmpf_collision,        ONLY : vMPF_AfterSplitting
USE MOD_Particle_Vars,         ONLY : usevMPF, PartMPF, RandomVec, Species
USE MOD_DSMC_ElectronicModel,  ONLY : ElectronicEnergyExchange
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES                                                                                
  INTEGER, INTENT(IN)           :: iPair, iReac
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  REAL                          :: FracMassCent1, FracMassCent2     ! mx/(mx+my)
  REAL                          :: VeloMx, VeloMy, VeloMz           ! center of mass velo
  REAL                          :: RanVelox, RanVeloy, RanVeloz     ! random relativ velo
  INTEGER                       :: iVec
  REAL                          :: JToEv, FakXi, Xi_rel, iRan
  INTEGER                       :: iQuaMax, iQua, React1Inx, React2Inx, NonReacPart
  REAL                          :: MaxColQua
  REAL                          :: ReacMPF
!===================================================================================================================================

JToEv = 1.602176565E-19

!..Get the index of react1 and the react2
  IF (PartSpecies(Coll_pData(iPair)%iPart_p1).EQ.ChemReac%DefinedReact(iReac,1,1)) THEN
    React1Inx = Coll_pData(iPair)%iPart_p1
    React2Inx = Coll_pData(iPair)%iPart_p2 
  ELSE
    React2Inx = Coll_pData(iPair)%iPart_p1
    React1Inx = Coll_pData(iPair)%iPart_p2
  END IF

  IF (usevMPF) THEN ! reaction MPF definition
    ReacMPF = MIN(PartMPF(React1Inx), PartMPF(React2Inx))
    IF (PartMPF(React1Inx).GT.ReacMPF) THEN ! just a part of the molecule 1 react
    !.... Get free particle index for the non-reacting particle part
      DSMCSumOfFormedParticles = DSMCSumOfFormedParticles + 1
      NonReacPart = PDM%nextFreePosition(DSMCSumOfFormedParticles+PDM%CurrentNextFreePosition)
      IF (NonReacPart.EQ.0) THEN
        CALL abort(__STAMP__,&
        'New Particle Number greater max Part Num in MolecExchange. Reaction: ',iReac)
      END IF
    ! Copy molecule data for non-reacting particle part
      PDM%ParticleInside(NonReacPart) = .true.
      PartSpecies(NonReacPart)        = PartSpecies(React1Inx)
      PartState(NonReacPart,1:6)      = PartState(React1Inx,1:6)
      PartStateIntEn(NonReacPart, 1)  = PartStateIntEn(React1Inx, 1)
      PartStateIntEn(NonReacPart, 2)  = PartStateIntEn(React1Inx, 2)
      IF (DSMC%ElectronicState) THEN
        PartStateIntEn(NonReacPart, 3)  = PartStateIntEn(React1Inx, 3)
      END IF
      PEM%Element(NonReacPart)        = PEM%Element(React1Inx)
      PartMPF(NonReacPart)            = PartMPF(React1Inx) - ReacMPF ! MPF of non-reacting particle part = MPF Diff
      PartMPF(React1Inx)              = ReacMPF ! reacting part MPF = ReacMPF
    ELSE IF (PartMPF(React2Inx).GT.ReacMPF) THEN ! just a part of the molecule 2 react
    !.... Get free particle index for the non-reacting particle part
      DSMCSumOfFormedParticles = DSMCSumOfFormedParticles + 1
      NonReacPart = PDM%nextFreePosition(DSMCSumOfFormedParticles+PDM%CurrentNextFreePosition)
      IF (NonReacPart.EQ.0) THEN
        CALL abort(__STAMP__,&
        'New Particle Number greater max Part Num in MolecExchange. Reaction: ',iReac)
      END IF
    ! Copy molecule data for non-reacting particle part
      PDM%ParticleInside(NonReacPart) = .true.
      PartSpecies(NonReacPart)        = PartSpecies(React2Inx)
      PartState(NonReacPart,1:6)      = PartState(React2Inx,1:6)
      PartStateIntEn(NonReacPart, 1)  = PartStateIntEn(React2Inx, 1)
      PartStateIntEn(NonReacPart, 2)  = PartStateIntEn(React2Inx, 2)
      IF (DSMC%ElectronicState) THEN
        PartStateIntEn(NonReacPart, 3)  = PartStateIntEn(React2Inx, 3)
      END IF
      PEM%Element(NonReacPart)        = PEM%Element(React2Inx)
      PartMPF(NonReacPart)            = PartMPF(React2Inx) - ReacMPF ! MPF of non-reacting particle part = MPF Diff
      PartMPF(React2Inx)              = ReacMPF ! reacting part MPF = ReacMPF
    END IF
  END IF

  ! Add heat of formation to collision energy
  Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec + ChemReac%EForm(iReac)

  !Set new Species of molec and atom
  PartSpecies(React1Inx) = ChemReac%DefinedReact(iReac,2,1)
  PartSpecies(React2Inx) = ChemReac%DefinedReact(iReac,2,2)

  Xi_rel = 2*(2 - SpecDSMC(PartSpecies(React1Inx))%omegaVHS) 
    ! DOF of relative motion in VHS model, only for one omega!!
    ! this is a result of the mean value of the relative energy in the vhs model, laux diss page 31
  FakXi = 0.5*(Xi_rel + SpecDSMC(PartSpecies(React1Inx))%Xi_Rot) - 1  

  ! check if electronic model is used
  IF ( DSMC%ElectronicState ) THEN
    ! add electronic energy to collision energy
    Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec + PartStateIntEn(Coll_pData(iPair)%iPart_p1,3) + &
                                                  PartStateIntEn(Coll_pData(iPair)%iPart_p2,3)
    CALL ElectronicEnergyExchange(Coll_pData(iPair)%Ec,React1Inx,FakXi,React2Inx,PEM%Element(React1Inx) )
    CALL ElectronicEnergyExchange(Coll_pData(iPair)%Ec,React2Inx,FakXi,React1Inx,PEM%Element(React2Inx) )
  END IF

  !Vibrational Relaxation of React1Inx
  MaxColQua = Coll_pData(iPair)%Ec/(BoltzmannConst*SpecDSMC(PartSpecies(React1Inx))%CharaTVib)  &
            - DSMC%GammaQuant
  iQuaMax = MIN(INT(MaxColQua) + 1, SpecDSMC(PartSpecies(React1Inx))%MaxVibQuant)
  CALL RANDOM_NUMBER(iRan)
  iQua = INT(iRan * iQuaMax)
  CALL RANDOM_NUMBER(iRan)
  DO WHILE (iRan.GT.(1 - iQua/MaxColQua)**FakXi) 
   !laux diss page 31
   CALL RANDOM_NUMBER(iRan)
   iQua = INT(iRan * iQuaMax)    
   CALL RANDOM_NUMBER(iRan)
  END DO
  PartStateIntEn(React1Inx,1) = (iQua + DSMC%GammaQuant) * BoltzmannConst &
                * SpecDSMC(PartSpecies(React1Inx))%CharaTVib 
  Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - PartStateIntEn(React1Inx,1) 

  !Rotational Relaxation of React1Inx
  CALL RANDOM_NUMBER(iRan)
  PartStateIntEn(React1Inx,2) = Coll_pData(iPair)%Ec * (1.0 - iRan**(1.0/FakXi))
  Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - PartStateIntEn(React1Inx,2) 

!--------------------------------------------------------------------------------------------------! 
! Calculation of new particle velocities
!--------------------------------------------------------------------------------------------------! 
  FracMassCent1 = CollInf%FracMassCent(ChemReac%DefinedReact(iReac,1,1), &
                CollInf%Coll_Case(ChemReac%DefinedReact(iReac,1,1),ChemReac%DefinedReact(iReac,1,2)))
  FracMassCent2 = CollInf%FracMassCent(ChemReac%DefinedReact(iReac,1,2), & 
                CollInf%Coll_Case(ChemReac%DefinedReact(iReac,1,1),ChemReac%DefinedReact(iReac,1,2)))

  !Calculation of velo from center of mass from old particle pair
  VeloMx = FracMassCent1 * PartState(React1Inx, 4) &
         + FracMassCent2 * PartState(React2Inx, 4)
  VeloMy = FracMassCent1 * PartState(React1Inx, 5) &
         + FracMassCent2 * PartState(React2Inx, 5)
  VeloMz = FracMassCent1 * PartState(React1Inx, 6) &
         + FracMassCent2 * PartState(React2Inx, 6)

  ! FracMassCent with the masses of products for calc of CRela2 and velo distribution
  FracMassCent1 = CollInf%FracMassCent(PartSpecies(React1Inx), CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(React2Inx)))
  FracMassCent2 = CollInf%FracMassCent(PartSpecies(React2Inx), CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(React2Inx)))

  !calculate random vec and new squared velocities
  Coll_pData(iPair)%CRela2 = 2 * Coll_pData(iPair)%Ec/ &
            CollInf%MassRed(CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(React2Inx)))
  CALL RANDOM_NUMBER(iRan)
  iVec = INT(NumRanVec * iRan + 1)
  RanVelox = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,1)
  RanVeloy = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,2)
  RanVeloz = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,3)

  !deltaV particle 1  
  DSMC_RHS(React1Inx,1) = VeloMx + FracMassCent2*RanVelox - PartState(React1Inx, 4)
  DSMC_RHS(React1Inx,2) = VeloMy + FracMassCent2*RanVeloy - PartState(React1Inx, 5)
  DSMC_RHS(React1Inx,3) = VeloMz + FracMassCent2*RanVeloz - PartState(React1Inx, 6)

  ! deltaV particle 2
  DSMC_RHS(React2Inx,1) = VeloMx - FracMassCent1*RanVelox - PartState(React2Inx, 4)
  DSMC_RHS(React2Inx,2) = VeloMy - FracMassCent1*RanVeloy - PartState(React2Inx, 5)
  DSMC_RHS(React2Inx,3) = VeloMz - FracMassCent1*RanVeloz - PartState(React2Inx, 6)

  IF(usevMPF) THEN
    IF (ReacMPF.GT.(Species(PartSpecies(React1Inx))%MacroParticleFactor)) THEN
      CALL vMPF_AfterSplitting(React1Inx, ReacMPF, Species(PartSpecies(React1Inx))%MacroParticleFactor)
    END IF
  END IF
  IF(usevMPF) THEN
    IF (ReacMPF.GT.(Species(PartSpecies(React2Inx))%MacroParticleFactor)) THEN
      CALL vMPF_AfterSplitting(React2Inx, ReacMPF, Species(PartSpecies(React2Inx))%MacroParticleFactor)
    END IF
  END IF

END SUBROUTINE MolecExch


SUBROUTINE AtomRecomb(iReac, iPair, iPart_p3)
!===================================================================================================================================
! Performs recombination between two atoms to one molecule
! atom recombination routine           A + B + X -> AB + X
!===================================================================================================================================
! MODULES
  USE MOD_Globals,               ONLY : abort
  USE MOD_DSMC_Vars,             ONLY : Coll_pData, DSMC_RHS, DSMC, CollInf, SpecDSMC
  USE MOD_DSMC_Vars,             ONLY : ChemReac, PartStateIntEn
  USE MOD_Particle_Vars,         ONLY : BoltzmannConst, PartSpecies, PartState, PDM, NumRanVec, RandomVec
  USE MOD_DSMC_ElectronicModel,  ONLY : ElectronicEnergyExchange
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES                                                                                
  INTEGER, INTENT(IN)           :: iPair, iReac, iPart_p3
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  REAL                          :: FracMassCent1, FracMassCent2     ! mx/(mx+my)
  REAL                          :: VeloMx, VeloMy, VeloMz           ! center of mass velo
  REAL                          :: RanVelox, RanVeloy, RanVeloz     ! random relativ velo
  INTEGER                       :: iVec
  REAL                          :: FakXi, Xi, iRan
  INTEGER                       :: iQuaMax, iQua, React1Inx, React2Inx
  REAL                          :: MaxColQua
! additional for Q-K theory
  REAL                          :: ksum, Tcoll
  INTEGER                       :: ii
!===================================================================================================================================

  IF (PartSpecies(Coll_pData(iPair)%iPart_p1).EQ.ChemReac%DefinedReact(iReac,1,1)) THEN
    React1Inx = Coll_pData(iPair)%iPart_p1
    React2Inx = Coll_pData(iPair)%iPart_p2
  ELSE
    React2Inx = Coll_pData(iPair)%iPart_p1
    React1Inx = Coll_pData(iPair)%iPart_p2
  END IF

  ! The input particle 1 is replaced by the product molecule, the
  !     second input particle is deleted
  PartSpecies(React1Inx) = ChemReac%DefinedReact(iReac,2,1)
  PDM%ParticleInside(React2Inx) = .FALSE.
  ! has to be calculated earlier because of setting of electronic energy
  Xi = 2.0 * (2.0 - SpecDSMC(PartSpecies(iPart_p3))%omegaVHS) + SpecDSMC(PartSpecies(iPart_p3))%Xi_Rot &
      + SpecDSMC(PartSpecies(React1Inx))%Xi_Rot
  FakXi = 0.5*Xi  - 1  ! exponent factor of DOF, substitute of Xi_c - Xi_vib, laux diss page 40

  ! check if atomic electron shell is modelled
  IF ( DSMC%ElectronicState ) THEN
  ! Add heat of formation to collision energy
    Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec + ChemReac%EForm(iReac) - PartStateIntEn(iPart_p3,1) + &
                           PartStateIntEn(Coll_pData(iPair)%iPart_p1,3) + PartStateIntEn(Coll_pData(iPair)%iPart_p2,3)
!--------------------------------------------------------------------------------------------------!
! electronic relaxation  of AB and X (if X is not an electron) 
!--------------------------------------------------------------------------------------------------!
    CALL ElectronicEnergyExchange(Coll_pData(iPair)%Ec,React1Inx,FakXi )
    Coll_pData(iPair)%Ec =  Coll_pData(iPair)%Ec + PartStateIntEn(iPart_p3,3)
    CALL ElectronicEnergyExchange(Coll_pData(iPair)%Ec,iPart_p3,FakXi )
  ELSE
  ! Add heat of formation to collision energy
    Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec + ChemReac%EForm(iReac) - PartStateIntEn(iPart_p3,1)
  END IF

!--------------------------------------------------------------------------------------------------! 
! Vibrational Relaxation of AB and X (if X is a molecule) 
!--------------------------------------------------------------------------------------------------!
  ! chose between Q-K and Arrhenius for detailed balancing
  IF ( ChemReac%QKProcedure(iReac) .EQV. .true. ) THEN
    MaxColQua = Coll_pData(iPair)%Ec/(BoltzmannConst*SpecDSMC(PartSpecies(React1Inx))%CharaTVib)  &
              - DSMC%GammaQuant
    iQuaMax = MIN(INT(MaxColQua) + 1, SpecDSMC(PartSpecies(React1Inx))%MaxVibQuant)
    ksum = 0.
    Tcoll = CollInf%MassRed(Coll_pData(iPair)%PairType)*Coll_pData(iPair)%CRela2  &
          / ( 2 * BoltzmannConst * ( 2 - SpecDSMC(PartSpecies(React1Inx))%omegaVHS ) )
    DO ii = 0, iQuaMax -1
      ksum = ksum + gammainc( [2. - SpecDSMC(PartSpecies(React1Inx))%omegaVHS,                          &
                               (iQuaMax - ii)*SpecDSMC(PartSpecies(React1Inx))%CharaTVib / Tcoll ] ) * &
             exp( - ii * SpecDSMC(PartSpecies(React1Inx))%CharaTVib / Tcoll )
    END DO
    CALL RANDOM_NUMBER(iRan)
    iQua = INT(iRan * iQuaMax)
    CALL RANDOM_NUMBER(iRan)
    DO WHILE (iRan.GT. ( gammainc([2. - SpecDSMC(PartSpecies(React1Inx))%omegaVHS,                          &
                               (iQuaMax - iQua)*SpecDSMC(PartSpecies(React1Inx))%CharaTVib / Tcoll ] ) *   &
                          exp( - iQua * SpecDSMC(PartSpecies(React1Inx))%CharaTVib/ Tcoll ) / ksum ) )
      ! diss page 31
      CALL RANDOM_NUMBER(iRan)
      iQua = INT(iRan * iQuaMax)    
      CALL RANDOM_NUMBER(iRan)
    END DO
    PartStateIntEn(React1Inx,1) = (iQua + DSMC%GammaQuant) * BoltzmannConst &
                  * SpecDSMC(PartSpecies(React1Inx))%CharaTVib
    Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - PartStateIntEn(React1Inx,1)+ PartStateIntEn(iPart_p3,1)
  ELSE


    MaxColQua = Coll_pData(iPair)%Ec/(BoltzmannConst*SpecDSMC(PartSpecies(React1Inx))%CharaTVib)  &
              - DSMC%GammaQuant
    iQuaMax = MIN(INT(MaxColQua) + 1, SpecDSMC(PartSpecies(React1Inx))%MaxVibQuant)
    CALL RANDOM_NUMBER(iRan)
    iQua = INT(iRan * iQuaMax)
    CALL RANDOM_NUMBER(iRan)
    DO WHILE (iRan.GT.(1 - iQua/MaxColQua)**FakXi) 
      !laux diss page 31
      CALL RANDOM_NUMBER(iRan)
      iQua = INT(iRan * iQuaMax)    
      CALL RANDOM_NUMBER(iRan)
    END DO
    PartStateIntEn(React1Inx,1) = (iQua + DSMC%GammaQuant) * BoltzmannConst &
                  * SpecDSMC(PartSpecies(React1Inx))%CharaTVib 
    Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - PartStateIntEn(React1Inx,1)+ PartStateIntEn(iPart_p3,1)
! X particle
    IF(SpecDSMC(PartSpecies(iPart_p3))%InterID.EQ. 2) THEN
      MaxColQua = Coll_pData(iPair)%Ec/(BoltzmannConst*SpecDSMC(PartSpecies(iPart_p3))%CharaTVib)  &
                - DSMC%GammaQuant
      iQuaMax = MIN(INT(MaxColQua) + 1, SpecDSMC(PartSpecies(iPart_p3))%MaxVibQuant)
      CALL RANDOM_NUMBER(iRan)
      iQua = INT(iRan * iQuaMax)
      CALL RANDOM_NUMBER(iRan)
      DO WHILE (iRan.GT.(1 - iQua/MaxColQua)**FakXi) 
      !laux diss page 31
      CALL RANDOM_NUMBER(iRan)
      iQua = INT(iRan * iQuaMax)    
      CALL RANDOM_NUMBER(iRan)
      END DO
      PartStateIntEn(iPart_p3,1) = (iQua + DSMC%GammaQuant) * BoltzmannConst &
                    * SpecDSMC(PartSpecies(iPart_p3))%CharaTVib 
      Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - PartStateIntEn(iPart_p3,1) 
    END IF
  END IF
!--------------------------------------------------------------------------------------------------! 
! rotational Relaxation of AB and X (if X is a molecule) 
!--------------------------------------------------------------------------------------------------!
  CALL RANDOM_NUMBER(iRan)
  PartStateIntEn(React1Inx,2) = Coll_pData(iPair)%Ec * (1.0 - iRan**(1.0/FakXi))
  Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - PartStateIntEn(React1Inx,2)
  IF(SpecDSMC(PartSpecies(iPart_p3))%InterID.EQ. 2) THEN
    CALL RANDOM_NUMBER(iRan)
    PartStateIntEn(iPart_p3,2) = Coll_pData(iPair)%Ec * (1.0 - iRan**(1.0/FakXi))
    Coll_pData(iPair)%Ec = Coll_pData(iPair)%Ec - PartStateIntEn(iPart_p3,2)
  END IF
!--------------------------------------------------------------------------------------------------! 
! Calculation of new particle velocities
!--------------------------------------------------------------------------------------------------!
  FracMassCent1 = CollInf%FracMassCent(PartSpecies(React1Inx), &
                  CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(iPart_p3)))
  FracMassCent2 = CollInf%FracMassCent(PartSpecies(iPart_p3), & 
                  CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(iPart_p3)))

  !Calculation of velo from center of mass
  VeloMx = FracMassCent1 * PartState(React1Inx, 4) &
         + FracMassCent2 * PartState(iPart_p3, 4)
  VeloMy = FracMassCent1 * PartState(React1Inx, 5) &
         + FracMassCent2 * PartState(iPart_p3, 5)
  VeloMz = FracMassCent1 * PartState(React1Inx, 6) &
         + FracMassCent2 * PartState(iPart_p3, 6)

  !calculate random vec and new squared velocities
  Coll_pData(iPair)%CRela2 = 2 * Coll_pData(iPair)%Ec/ &
            CollInf%MassRed(CollInf%Coll_Case(PartSpecies(React1Inx),PartSpecies(iPart_p3)))
  CALL RANDOM_NUMBER(iRan)
  iVec = INT(NumRanVec * iRan + 1)
  RanVelox = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,1)
  RanVeloy = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,2)
  RanVeloz = SQRT(Coll_pData(iPair)%CRela2) * RandomVec(iVec,3)

  ! deltaV particle 1
  DSMC_RHS(React1Inx,1) = VeloMx + FracMassCent2*RanVelox - PartState(React1Inx, 4)
  DSMC_RHS(React1Inx,2) = VeloMy + FracMassCent2*RanVeloy - PartState(React1Inx, 5)
  DSMC_RHS(React1Inx,3) = VeloMz + FracMassCent2*RanVeloz - PartState(React1Inx, 6)

 ! deltaV particle 2
  DSMC_RHS(iPart_p3,1) = VeloMx - FracMassCent1*RanVelox - PartState(iPart_p3, 4)
  DSMC_RHS(iPart_p3,2) = VeloMy - FracMassCent1*RanVeloy - PartState(iPart_p3, 5)
  DSMC_RHS(iPart_p3,3) = VeloMz - FracMassCent1*RanVeloz - PartState(iPart_p3, 6)

END SUBROUTINE AtomRecomb


SUBROUTINE simpleCEX(iReac, iPair)
!===================================================================================================================================
! simple charge exchange interaction     
! ION(v1) + ATOM(v2) -> ATOM(v1) + ION(v2)
!===================================================================================================================================
! MODULES
  USE MOD_DSMC_Vars,             ONLY : Coll_pData, DSMC_RHS
  USE MOD_DSMC_Vars,             ONLY : ChemReac
  USE MOD_Particle_Vars,         ONLY : PartSpecies
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES                                                                                
  INTEGER, INTENT(IN)           :: iPair, iReac
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  INTEGER                       :: React1Inx, React2Inx
!===================================================================================================================================

  IF (PartSpecies(Coll_pData(iPair)%iPart_p1).EQ.ChemReac%DefinedReact(iReac,1,1)) THEN
    React1Inx = Coll_pData(iPair)%iPart_p1
    React2Inx = Coll_pData(iPair)%iPart_p2
  ELSE
    React2Inx = Coll_pData(iPair)%iPart_p1
    React1Inx = Coll_pData(iPair)%iPart_p2
  END IF
  ! change species
  PartSpecies(React1Inx) = ChemReac%DefinedReact(iReac,2,1)
  PartSpecies(React2Inx) = ChemReac%DefinedReact(iReac,2,2)
  ! deltaV particle 1
  DSMC_RHS(Coll_pData(iPair)%iPart_p1,1) = 0.
  DSMC_RHS(Coll_pData(iPair)%iPart_p1,2) = 0.
  DSMC_RHS(Coll_pData(iPair)%iPart_p1,3) = 0.
  ! deltaV particle 2
  DSMC_RHS(Coll_pData(iPair)%iPart_p2,1) = 0.
  DSMC_RHS(Coll_pData(iPair)%iPart_p2,2) = 0.
  DSMC_RHS(Coll_pData(iPair)%iPart_p2,3) = 0.

END SUBROUTINE simpleCEX

SUBROUTINE SetMeanVibQua()
!===================================================================================================================================
! Computes the vibrational quant of species
!===================================================================================================================================
! MODULES
  USE MOD_DSMC_Vars,             ONLY : DSMC, CollInf, SpecDSMC, ChemReac, BGGas
  USE MOD_Particle_Vars,         ONLY : BoltzmannConst, nSpecies
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES                                                                                
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  INTEGER         :: iSpec
  REAL            :: iRan, VibQuaTemp
!===================================================================================================================================

  DO iSpec =1, nSpecies
    ! describe evib as quantum number
    IF (iSpec.EQ.BGGas%BGGasSpecies) THEN
      ChemReac%MeanEVibQua_PerIter(iSpec) = BGGas%BGMeanEVibQua
    ELSE
      IF(SpecDSMC(iSpec)%PolyatomicMol.AND.(CollInf%Coll_SpecPartNum(iSpec).NE.0)) THEN
        ChemReac%MeanEVib_PerIter(iSpec) = ChemReac%MeanEVib_PerIter(iSpec) / CollInf%Coll_SpecPartNum(iSpec)
      ELSEIF ((CollInf%Coll_SpecPartNum(iSpec).NE.0).AND.(SpecDSMC(iSpec)%CharaTVib.NE.0)) THEN
        ChemReac%MeanEVib_PerIter(iSpec) = ChemReac%MeanEVib_PerIter(iSpec) / CollInf%Coll_SpecPartNum(iSpec)
        VibQuaTemp = ChemReac%MeanEVib_PerIter(iSpec) / (BoltzmannConst*SpecDSMC(iSpec)%CharaTVib) - DSMC%GammaQuant
        CALL RANDOM_NUMBER(iRan)
        IF((VibQuaTemp-INT(VibQuaTemp)).GT.iRan) THEN
          ChemReac%MeanEVibQua_PerIter(iSpec) = MIN(INT(VibQuaTemp) + 2, SpecDSMC(iSpec)%MaxVibQuant-1)
        ELSE
          ChemReac%MeanEVibQua_PerIter(iSpec) = MIN(INT(VibQuaTemp) + 1, SpecDSMC(iSpec)%MaxVibQuant-1)
        END IF
      ELSE
        ChemReac%MeanEVibQua_PerIter(iSpec) = 0
      END IF
    END IF
  END DO
END SUBROUTINE SetMeanVibQua


RECURSIVE FUNCTION lacz_gamma(a) RESULT(g)
!===================================================================================================================================
! gamma function taken from
! http://rosettacode.org/wiki/Gamma_function#Fortran
! variefied against build in and compiled with double precision
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES                                                                                
  REAL(KIND=8), INTENT(IN) :: a
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
  REAL(KIND=8) :: g
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  REAL(KIND=8), PARAMETER :: pi = 3.14159265358979324
  INTEGER, PARAMETER :: cg = 7
  ! these precomputed values are taken by the sample code in Wikipedia,
  ! and the sample itself takes them from the GNU Scientific Library
  REAL(KIND=8), DIMENSION(0:8), PARAMETER :: p = &
       (/ 0.99999999999980993, 676.5203681218851, -1259.1392167224028, &
       771.32342877765313, -176.61502916214059, 12.507343278686905, &
       -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7 /)
  REAL(KIND=8) :: t, w, x
  INTEGER :: i
!===================================================================================================================================

  x = a

  IF ( x < 0.5 ) THEN
     g = pi / ( sin(pi*x) * lacz_gamma(1.0-x) )
  ELSE
     x = x - 1.0
     t = p(0)
     DO i=1, cg+2
        t = t + p(i)/(x+real(i))
     END DO
     w = x + real(cg) + 0.5
     g = sqrt(2.0*pi) * w**(x+0.5) * exp(-w) * t
  END IF
END FUNCTION lacz_gamma


FUNCTION gammainc( arg )
!===================================================================================================================================
! Program to test the incomplete gamma function
! the following gamma function is the one of Birds Q-K rate code
! ev. take another gamma function implementation
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES                                                                                
  INTEGER,PARAMETER              :: real_kind=8
  REAL(KIND=real_kind),DIMENSION(1:2), INTENT(IN) :: arg
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  INTEGER                        :: n
  REAL(KIND=real_kind)           :: gamser, gln, ap, del, summ, an, ser, tmp, x,y, b,c,d,h
  REAL(KIND=real_kind)           :: gammainc
  ! parameters
  REAL(KIND=real_kind),PARAMETER,DIMENSION(6) :: &
                                      cof= [ 76.18009172947146      , &
                                            -86.50532032941677     , &
                                             24.01409824083091      , &
                                             -1.231739572450155     , &
                                              0.1208650973866179e-2  , &
                                            -0.5395239384953e-5 ]
  REAL(KIND=real_kind),PARAMETER :: stp=2.5066282746310005        , &
                                    fpmin=1.e-30
!===================================================================================================================================

  x=arg(1)
  y=x
  tmp=x+5.5
  tmp=(x+0.5)*log(tmp)-tmp
  ser=1.000000000190015
  DO n = 1, 6
    y=y+1.
    ser=ser+cof(n)/y
  END DO
  gln=tmp+log(stp*ser/x)
  IF (arg(2) < arg(1)+1.) THEN
    IF (arg(2) <= 0.) THEN
      gamser=0.
    ELSE
      ap=arg(1)
      summ=1./arg(1)
      del=summ
      DO WHILE (abs(del) > abs(summ)*1.e-8 )
        ap=ap+1.
        del=del*arg(2)/ap
        summ=summ+del
      END DO
      gamser=summ*exp(-arg(2)+arg(1)*log(arg(2))-gln)
    END IF
    gammainc=1.-gamser
  ELSE
    b =arg(2)+1.-arg(1)
    c=1./fpmin
    d=1./b
    h=d
    del=d*c
    n=0
    DO WHILE ( abs(del-1.) >= 1.e-8 )
      n=n+1
      an=-n*(n-arg(1))
      b=b+2.
      d=an*d+b
      IF ( abs(d) < fpmin ) THEN
        d=fpmin
      END IF
      c=b+an/c
      IF ( abs(c) < fpmin ) THEN
        c=fpmin
      END IF
      d=1./d
      del=d*c
      h=h*del
    END DO
    gammainc=exp(-arg(2)+arg(1)*log(arg(2))-gln) * h
  END IF
END FUNCTION gammainc

END MODULE MOD_DSMC_ChemReact
