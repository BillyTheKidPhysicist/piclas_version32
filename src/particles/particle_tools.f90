!==================================================================================================================================
! Copyright (c) 2010 - 2018 Prof. Claus-Dieter Munz and Prof. Stefanos Fasoulas
!
! This file is part of PICLas (gitlab.com/piclas/piclas). PICLas is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3
! of the License, or (at your option) any later version.
!
! PICLas is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with PICLas. If not, see <http://www.gnu.org/licenses/>.
!==================================================================================================================================
#include "piclas.h"

MODULE MOD_part_tools
!===================================================================================================================================
! Contains tools for particle related operations. This routine uses MOD_Particle_Boundary_Tools, but not vice versa!
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

INTERFACE UpdateNextFreePosition
  MODULE PROCEDURE UpdateNextFreePosition
END INTERFACE

INTERFACE VeloFromDistribution
  MODULE PROCEDURE VeloFromDistribution
END INTERFACE

INTERFACE DiceUnitVector
  MODULE PROCEDURE DiceUnitVector
END INTERFACE

INTERFACE isChargedParticle
  MODULE PROCEDURE isChargedParticle
END INTERFACE

INTERFACE isPushParticle
  MODULE PROCEDURE isPushParticle
END INTERFACE

INTERFACE isDepositParticle
  MODULE PROCEDURE isDepositParticle
END INTERFACE

INTERFACE isInterpolateParticle
  MODULE PROCEDURE isInterpolateParticle
END INTERFACE

INTERFACE StoreLostParticleProperties
  MODULE PROCEDURE StoreLostParticleProperties
END INTERFACE

!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
PUBLIC :: UpdateNextFreePosition, DiceUnitVector, VeloFromDistribution, GetParticleWeight, CalcRadWeightMPF, isChargedParticle
PUBLIC :: isPushParticle, isDepositParticle, isInterpolateParticle, StoreLostParticleProperties, BuildTransGaussNums
PUBLIC :: CalcXiElec,ParticleOnProc
!===================================================================================================================================

CONTAINS

SUBROUTINE UpdateNextFreePosition()
!===================================================================================================================================
! Updates next free position
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_Vars        ,ONLY: PDM,PEM, PartSpecies, doParticleMerge, vMPF_SpecNumElem
USE MOD_Particle_Vars        ,ONLY: PartState, VarTimeStep, usevMPF
USE MOD_DSMC_Vars            ,ONLY: useDSMC, CollInf
USE MOD_Particle_VarTimeStep ,ONLY: CalcVarTimeStep
#if USE_LOADBALANCE
USE MOD_LoadBalance_Timers   ,ONLY: LBStartTime,LBSplitTime,LBPauseTime
#endif /*USE_LOADBALANCE*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER            :: counter1,i,n
INTEGER            :: ElemID
#if !USE_MPI
INTEGER            :: OffSetElemMPI(0) = 0            !> Dummy offset for single-thread mode
#endif
#if USE_LOADBALANCE
REAL               :: tLBStart
#endif /*USE_LOADBALANCE*/
!===================================================================================================================================
#if USE_LOADBALANCE
CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/

IF(PDM%maxParticleNumber.EQ.0) RETURN
counter1 = 1
IF (useDSMC.OR.doParticleMerge.OR.usevMPF) THEN
  PEM%pNumber(:) = 0
END IF

n = PDM%ParticleVecLength !PDM%maxParticleNumber

! Check size of PDM%ParticleInside array vs. PDM%ParticleVecLength. During particle splitting, the max particle number might be
! exceeded, which may lead to an out-of-bounds here
IF(usevMPF)THEN
  IF(n.GT.SIZE(PDM%ParticleInside))THEN
    IPWRITE(UNIT_StdOut,*) "PDM%ParticleVecLength    :", PDM%ParticleVecLength
    IPWRITE(UNIT_StdOut,*) "SIZE(PDM%ParticleInside) :", SIZE(PDM%ParticleInside)
    CALL abort(__STAMP__,'PDM%ParticleVecLength exceeds allocated arrays. Possible vMPF overflow.')
  END IF ! n.GT.SIZE(PDM%ParticleInside)
END IF ! usevMPF

! Nullify
PDM%ParticleVecLength = 0
PDM%insideParticleNumber = 0
IF (doParticleMerge) vMPF_SpecNumElem = 0

IF (useDSMC.OR.doParticleMerge.OR.usevMPF) THEN
  DO i=1,n
    IF (.NOT.PDM%ParticleInside(i)) THEN
      IF (CollInf%ProhibitDoubleColl) CollInf%OldCollPartner(i) = 0
      PDM%nextFreePosition(counter1) = i
      counter1 = counter1 + 1
    ELSE
      ! Sanity check corrupted particle list (some or all entries of a particle become zero, including the species ID)
      IF(PartSpecies(i).LE.0) CALL abort(__STAMP__,'Species ID is zero for ipart=',IntInfoOpt=i)
      ElemID = PEM%LocalElemID(i)
      IF (PEM%pNumber(ElemID).EQ.0) THEN
        PEM%pStart(ElemID) = i                     ! Start of Linked List for Particles in Elem
      ELSE
        PEM%pNext(PEM%pEnd(ElemID)) = i            ! Next Particle of same Elem (Linked List)
      END IF
      PEM%pEnd(ElemID) = i
      PEM%pNumber(ElemID) = &                      ! Number of Particles in Element
          PEM%pNumber(ElemID) + 1
      IF (VarTimeStep%UseVariableTimeStep) THEN
        VarTimeStep%ParticleTimeStep(i) = CalcVarTimeStep(PartState(1,i),PartState(2,i),ElemID)
      END IF
      PDM%ParticleVecLength = i
      IF(doParticleMerge) vMPF_SpecNumElem(ElemID,PartSpecies(i)) = vMPF_SpecNumElem(ElemID,PartSpecies(i)) + 1
    END IF
  END DO
ELSE ! no DSMC
  DO i=1,n
    IF (.NOT.PDM%ParticleInside(i)) THEN
      PDM%nextFreePosition(counter1) = i
      counter1 = counter1 + 1
    ELSE
      PDM%ParticleVecLength = i
    END IF
  END DO
ENDIF
PDM%insideParticleNumber = PDM%ParticleVecLength - counter1+1
PDM%CurrentNextFreePosition = 0
DO i = n+1,PDM%maxParticleNumber
  IF (CollInf%ProhibitDoubleColl) CollInf%OldCollPartner(i) = 0
  PDM%nextFreePosition(counter1) = i
  counter1 = counter1 + 1
END DO
PDM%nextFreePosition(counter1:PDM%MaxParticleNumber)=0 ! exists if MaxParticleNumber is reached!!!
IF (counter1.GT.PDM%MaxParticleNumber) PDM%nextFreePosition(PDM%MaxParticleNumber)=0

#if USE_LOADBALANCE
CALL LBPauseTime(LB_UNFP,tLBStart)
#endif /*USE_LOADBALANCE*/

  RETURN
END SUBROUTINE UpdateNextFreePosition


SUBROUTINE StoreLostParticleProperties(iPart,ElemID,UsePartState_opt,PartMissingType_opt)
!----------------------------------------------------------------------------------------------------------------------------------!
! Store information of a lost particle (during restart and during the simulation)
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
USE MOD_Globals                ,ONLY: abort,myrank
USE MOD_Particle_Vars          ,ONLY: usevMPF,PartMPF,PartSpecies,Species,PartState,LastPartPos
USE MOD_Particle_Tracking_Vars ,ONLY: PartStateLost,PartLostDataSize,PartStateLostVecLength
USE MOD_TimeDisc_Vars          ,ONLY: time
!----------------------------------------------------------------------------------------------------------------------------------!
! insert modules here
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES 
INTEGER,INTENT(IN)          :: iPart
INTEGER,INTENT(IN)          :: ElemID ! Global element index
LOGICAL,INTENT(IN),OPTIONAL :: UsePartState_opt
INTEGER,INTENT(IN),OPTIONAL :: PartMissingType_opt ! 0: lost, 1: missing & found once, >1: missing & multiply found
INTEGER                     :: dims(2)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                 :: MPF
! Temporary arrays
REAL, ALLOCATABLE    :: PartStateLost_tmp(:,:)   ! (1:11,1:NParts) 1st index: x,y,z,vx,vy,vz,SpecID,MPF,time,ElemID,iPart
!                                                !                 2nd index: 1 to number of lost particles
INTEGER              :: ALLOCSTAT
LOGICAL              :: UsePartState_loc
!===================================================================================================================================
UsePartState_loc = .FALSE.
IF (PRESENT(UsePartState_opt)) UsePartState_loc = UsePartState_opt

! Set macro particle factor
IF (usevMPF) THEN
  MPF = PartMPF(iPart)
ELSE
  MPF = Species(PartSpecies(iPart))%MacroParticleFactor
END IF

dims = SHAPE(PartStateLost)

ASSOCIATE( iMax => PartStateLostVecLength )
  ! Increase maximum number of boundary-impact particles
  iMax = iMax + 1

  ! Check if array maximum is reached. 
  ! If this happens, re-allocate the arrays and increase their size (every time this barrier is reached, double the size)
  IF(iMax.GT.dims(2))THEN

    ! --- PartStateLost ---
    ALLOCATE(PartStateLost_tmp(1:PartLostDataSize,1:dims(2)), STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) CALL abort(&
          __STAMP__&
          ,'ERROR in particle_boundary_tools.f90: Cannot allocate PartStateLost_tmp temporary array!')
    ! Save old data
    PartStateLost_tmp(1:PartLostDataSize,1:dims(2)) = PartStateLost(1:PartLostDataSize,1:dims(2))

    ! Re-allocate PartStateLost to twice the size
    DEALLOCATE(PartStateLost)
    ALLOCATE(PartStateLost(1:PartLostDataSize,1:2*dims(2)), STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) CALL abort(&
          __STAMP__&
          ,'ERROR in particle_boundary_tools.f90: Cannot allocate PartStateLost array!')
    PartStateLost(1:PartLostDataSize,        1:  dims(2)) = PartStateLost_tmp(1:PartLostDataSize,1:dims(2))
    PartStateLost(1:PartLostDataSize,dims(2)+1:2*dims(2)) = 0.

  END IF

  ! 1-3: Particle position (last valid position)
  IF(UsePartState_loc)THEN
    PartStateLost(1:3,iMax) = PartState(1:3,iPart)
  ELSE
    PartStateLost(1:3,iMax) = LastPartPos(1:3,iPart)
  END IF ! UsePartState_loc
  ! 4-6: Particle velocity
  PartStateLost(4:6  ,iMax) = PartState(4:6,iPart)
  ! 7: SpeciesID
  PartStateLost(7    ,iMax) = REAL(PartSpecies(iPart))
  ! 8: Macro particle factor
  PartStateLost(8    ,iMax) = MPF
  ! 9: time of loss
  PartStateLost(9    ,iMax) = time
  ! 10: Global element ID
  PartStateLost(10   ,iMax) = REAL(ElemID)
  ! 11: Particle ID
  PartStateLost(11   ,iMax) = REAL(iPart)
  ! 12-14: Particle position (position of loss)
  PartStateLost(12:14,iMax) = PartState(1:3,iPart)
  ! 15: myrank
  PartStateLost(15,iMax) = myrank
  ! 16: missing type, i.e., 0: lost, 1: missing & found once, >1: missing & multiply found
  IF(PRESENT(PartMissingType_opt))THEN ! when particles go missing during restart (maybe they are found on other procs or lost)
    PartStateLost(16,iMax) = PartMissingType_opt
  ELSE ! simply lost during the simulation
    PartStateLost(16,iMax) = 0
  END IF ! PRESENT(PartMissingType_opt)
END ASSOCIATE

END SUBROUTINE StoreLostParticleProperties


FUNCTION DiceUnitVector()
!===================================================================================================================================
!> Calculates random unit vector
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
USE MOD_Globals_Vars ,ONLY: Pi
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  REAL                     :: DiceUnitVector(3)
  REAL                     :: rRan, cos_scatAngle, sin_scatAngle, rotAngle
!===================================================================================================================================
  CALL RANDOM_NUMBER(rRan)

  cos_scatAngle     = 2.*rRan-1.
  sin_scatAngle     = SQRT(1. - cos_scatAngle ** 2.)
  DiceUnitVector(1) = cos_scatAngle

  CALL RANDOM_NUMBER(rRan)
  rotAngle          = 2. * Pi * rRan

  DiceUnitVector(2) = sin_scatAngle * COS(rotAngle)
  DiceUnitVector(3) = sin_scatAngle * SIN(rotAngle)

END FUNCTION DiceUnitVector


!===================================================================================================================================
!> Calculation of velocity vector (Vx,Vy,Vz) sampled from given distribution function
!===================================================================================================================================
FUNCTION VeloFromDistribution(distribution,Tempergy,iNewPart,ProductSpecNbr)
! MODULES
USE MOD_Globals           ,ONLY: Abort,UNIT_stdOut,VECNORM
USE MOD_Globals_Vars      ,ONLY: eV2Joule,ElectronMass,c
USE MOD_SurfaceModel_Vars ,ONLY: BackupVeloABS
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN) :: distribution   !< Specifying keyword for velocity distribution
REAL,INTENT(IN)             :: Tempergy       !< Input temperature in [K] or energy in [J] or [eV] or velocity in [m/s]
INTEGER,INTENT(IN)          :: iNewPart       !< The i-th particle that is inserted (only required for some distributions)
INTEGER,INTENT(IN)          :: ProductSpecNbr !< Total number of particles that are inserted (only required for some distributions)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL            :: VeloFromDistribution(1:3) !< Velocity vector created from specific velocity distribution function
REAL            :: VeloABS                   !< Absolute velocity of the velocity vector
REAL            :: RandVal                   !< Pseudo random number
LOGICAL         :: ARM                       !< Acceptance rejection method
REAL            :: PDF                       !< Probability density function
REAL            :: eps,eps2                  !< kinetic electron energy [eV]
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
!-- set velocities
SELECT CASE(TRIM(distribution))

CASE('deltadistribution')

  ! Get random vector
  VeloFromDistribution = DiceUnitVector()
  ! Mirror z-component of velocity (particles are emitted from surface!)
  VeloFromDistribution(3) = ABS(VeloFromDistribution(3))
  ! Set magnitude
  VeloFromDistribution = Tempergy*VeloFromDistribution ! Tempergy here is [m/s]

CASE('Morozov2004') ! Secondary electron emission (SEE) due to electron bombardment on dielectric surfaces

  IF(ProductSpecNbr.EQ.1)THEN ! 1 SEE

    ! ARM for energy distribution
    ARM = .TRUE.
    DO WHILE(ARM)
      CALL RANDOM_NUMBER(RandVal) ! random x-coordinate
      PDF = 4.0*RandVal*(1.0-RandVal)
      eps = RandVal ! RandVal is eps/eps_p (relative energy as compared with the incident electron energy)
      CALL RANDOM_NUMBER(RandVal) ! random y-coordinate
      IF (RandVal.LT.PDF) ARM = .FALSE.
    END DO
    VeloABS = SQRT(2.0 * eps * Tempergy * eV2Joule / ElectronMass) ! Tempergy here is [eV], which is converted from eV to J

  ELSE ! 2 SEE

    ! ARM for energy distribution
    IF(iNewPart.EQ.1)THEN ! 1st call
      ARM = .TRUE.
      DO WHILE(ARM)
        ! Pick 1st electron energy
        CALL RANDOM_NUMBER(RandVal)
        PDF = 4.0*RandVal*(1.0-RandVal)
        eps = RandVal ! RandVal is eps/eps_p (relative energy as compared with the incident electron energy)
        CALL RANDOM_NUMBER(RandVal)
        IF (RandVal.LT.PDF)THEN
          ! Pick 2nd electron energy
          CALL RANDOM_NUMBER(RandVal)
          PDF = 4.0*RandVal*(1.0-RandVal)
          eps2 = RandVal ! RandVal is eps/eps_p (relative energy as compared with the incident electron energy)
          CALL RANDOM_NUMBER(RandVal)
          IF(RandVal.LT.PDF)THEN
            ARM = .FALSE. ! success, skip this loop and skip the outer loop
            ! eV to J: store 2nd electron velocity for next function call
            BackupVeloABS = SQRT(2.0 * eps2 * Tempergy * eV2Joule / ElectronMass) ! Tempergy here is [eV] (converted from eV to J)
            IF(eps+eps2.GT.1.0) ARM = .TRUE. ! start again for both energies
          END IF
        END IF
      END DO
      VeloABS = SQRT(2.0 * eps * Tempergy * eV2Joule / ElectronMass) ! Tempergy here is [eV], which is converted from eV to J

    ELSE ! 2nd call of this function, velocity already known from last call and stored in "BackupVeloABS"

      VeloABS = BackupVeloABS

    END IF ! iNewPart.EQ.1

  END IF ! ProductSpecNbr.EQ.1

  ! Get random vector
  VeloFromDistribution = DiceUnitVector()
  ! Mirror z-component of velocity (particles are emitted from surface!)
  VeloFromDistribution(3) = ABS(VeloFromDistribution(3))
  ! Set magnitude
  VeloFromDistribution = VeloABS*VeloFromDistribution ! VeloABS is [m/s]

CASE DEFAULT

  CALL abort(__STAMP__,'Unknown velocity dsitribution: ['//TRIM(distribution)//']')

END SELECT

! Sanity check: is the newly created particle faster than c
IF(VECNORM(VeloFromDistribution).GT.c) CALL abort(__STAMP__,'VeloFromDistribution: Particle is faster than the speed of light: ',&
    RealInfoOpt=VeloABS)

END FUNCTION VeloFromDistribution


PPURE REAL FUNCTION GetParticleWeight(iPart)
!===================================================================================================================================
!> Determines the appropriate particle weighting for the axisymmetric case with radial weighting and the variable time step. For
!> radial weighting, the radial factor is multiplied by the regular weighting factor. If only a variable time step is used, at the
!> moment, the regular weighting factor is not included.
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
USE MOD_Particle_Vars           ,ONLY: usevMPF, VarTimeStep, PartMPF
USE MOD_DSMC_Vars               ,ONLY: RadialWeighting
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN)             :: iPart
!===================================================================================================================================

IF(usevMPF.OR.RadialWeighting%DoRadialWeighting) THEN
  IF (VarTimeStep%UseVariableTimeStep) THEN
    GetParticleWeight = PartMPF(iPart) * VarTimeStep%ParticleTimeStep(iPart)
  ELSE
    GetParticleWeight = PartMPF(iPart)
  END IF
ELSE IF (VarTimeStep%UseVariableTimeStep) THEN
  GetParticleWeight = VarTimeStep%ParticleTimeStep(iPart)
ELSE
  GetParticleWeight = 1.
END IF

END FUNCTION GetParticleWeight


PPURE REAL FUNCTION CalcRadWeightMPF(yPos, iSpec, iPart)
!===================================================================================================================================
!> Determines the weighting factor when using an additional radial weighting for axisymmetric simulations. Linear increase from the
!> rotational axis (y=0) to the outer domain boundary (y=ymax).
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_DSMC_Vars               ,ONLY: RadialWeighting
USE MOD_Particle_Vars           ,ONLY: Species, PEM
USE MOD_Particle_Mesh_Vars      ,ONLY: GEO
USE MOD_Particle_Mesh_Vars      ,ONLY: ElemMidPoint_Shared
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                :: yPos
INTEGER, INTENT(IN)             :: iSpec
INTEGER, OPTIONAL,INTENT(IN)    :: iPart
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
REAL                 :: yPosIn
!===================================================================================================================================

IF(RadialWeighting%CellLocalWeighting.AND.PRESENT(iPart)) THEN
  yPosIn = ElemMidPoint_Shared(2,PEM%CNElemID(iPart))
ELSE
  yPosIn = yPos
END IF

CalcRadWeightMPF = (1. + yPosIn/GEO%ymaxglob*(RadialWeighting%PartScaleFactor-1.))*Species(iSpec)%MacroParticleFactor

RETURN

END FUNCTION CalcRadWeightMPF


PPURE FUNCTION isChargedParticle(iPart)
!----------------------------------------------------------------------------------------------------------------------------------!
! Check if particle has charge unequal to zero and return T/F logical.
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Particle_Vars ,ONLY: PartSpecies,Species
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES
INTEGER,INTENT(IN)  :: iPart
LOGICAL             :: isChargedParticle
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
IF(ABS(Species(PartSpecies(iPart))%ChargeIC).GT.0.0)THEN
  isChargedParticle = .TRUE.
ELSE
  isChargedParticle = .FALSE.
END IF ! ABS(Species(PartSpecies(iPart))%ChargeIC).GT.0.0
END FUNCTION isChargedParticle


PPURE FUNCTION isPushParticle(iPart)
!----------------------------------------------------------------------------------------------------------------------------------!
! Check if particle is to be evolved in time by the particle pusher (time integration).
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
#if (PP_TimeDiscMethod==300) /*FP-Flow*/
USE MOD_Particle_Vars ,ONLY: PartSpecies,Species ! Change this when required
#elif (PP_TimeDiscMethod==400) /*BGK*/
USE MOD_Particle_Vars ,ONLY: PartSpecies,Species ! Change this when required
#else /*all other methods, mainly PIC*/
USE MOD_Particle_Vars ,ONLY: PartSpecies,Species
#endif
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES
INTEGER,INTENT(IN)  :: iPart
LOGICAL             :: isPushParticle
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
IF(ABS(Species(PartSpecies(iPart))%ChargeIC).GT.0.0)THEN
  isPushParticle = .TRUE.
ELSE
  isPushParticle = .FALSE.
END IF ! ABS(Species(PartSpecies(iPart))%ChargeIC).GT.0.0
END FUNCTION isPushParticle


PPURE FUNCTION isDepositParticle(iPart)
!----------------------------------------------------------------------------------------------------------------------------------!
! Check if particle is to be deposited on the grid (particle-to-grid coupling).
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
#if (PP_TimeDiscMethod==300) /*FP-Flow*/
USE MOD_Particle_Vars ,ONLY: PartSpecies,Species ! Change this when required
#elif (PP_TimeDiscMethod==400) /*BGK*/
USE MOD_Particle_Vars ,ONLY: PartSpecies,Species ! Change this when required
#else /*all other methods, mainly PIC*/
USE MOD_Particle_Vars ,ONLY: PartSpecies,Species
#endif
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES
INTEGER,INTENT(IN)  :: iPart
LOGICAL             :: isDepositParticle
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
IF(ABS(Species(PartSpecies(iPart))%ChargeIC).GT.0.0)THEN
  isDepositParticle = .TRUE.
ELSE
  isDepositParticle = .FALSE.
END IF ! ABS(Species(PartSpecies(iPart))%ChargeIC).GT.0.0
END FUNCTION isDepositParticle


PPURE FUNCTION isInterpolateParticle(iPart)
!----------------------------------------------------------------------------------------------------------------------------------!
! Check if particle is to be interpolated (field-to-particle coupling), which is required for calculating the acceleration, e.g.,
! due to Lorentz forces at the position of the particle.
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
#if (PP_TimeDiscMethod==300) /*FP-Flow*/
USE MOD_Particle_Vars ,ONLY: PartSpecies,Species ! Change this when required
#elif (PP_TimeDiscMethod==400) /*BGK*/
USE MOD_Particle_Vars ,ONLY: PartSpecies,Species ! Change this when required
#else /*all other methods, mainly PIC*/
USE MOD_Particle_Vars ,ONLY: PartSpecies,Species
#endif
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES
INTEGER,INTENT(IN)  :: iPart
LOGICAL             :: isInterpolateParticle
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
IF(ABS(Species(PartSpecies(iPart))%ChargeIC).GT.0.0)THEN
  isInterpolateParticle = .TRUE.
ELSE
  isInterpolateParticle = .FALSE.
END IF ! ABS(Species(PartSpecies(iPart))%ChargeIC).GT.0.0
END FUNCTION isInterpolateParticle


SUBROUTINE BuildTransGaussNums(nPart, iRanPart)
!===================================================================================================================================
!> Builds random Gauss numbers with a zero mean and a variance of one
!===================================================================================================================================
! MODULES
USE Ziggurat
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN)           :: nPart
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL, INTENT(OUT)             :: iRanPart(:,:)
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                           :: sumiRan(3), varianceiRan(3)
INTEGER                        :: iLoop,I
!===================================================================================================================================
sumiRan(1:3) = 0.0
varianceiRan(1:3) = 0.0
DO iLoop = 1, nPart
  iRanPart(1,iLoop) = rnor()
  iRanPart(2,iLoop) = rnor()
  iRanPart(3,iLoop) = rnor()
  sumiRan(1:3) = sumiRan(1:3) + iRanPart(1:3,iLoop)
END DO
sumiRan(1:3) = sumiRan(1:3)/nPart
DO iLoop = 1, nPart
  iRanPart(1:3,iLoop) = iRanPart(1:3,iLoop)-sumiRan(1:3)
  varianceiRan(1:3) = varianceiRan(1:3) + iRanPart(1:3,iLoop)*iRanPart(1:3,iLoop)
END DO
varianceiRan(1:3) = SQRT(varianceiRan(1:3)/nPart)

DO iLoop = 1, nPart
  DO I = 1, 3
    IF(varianceiRan(I).GT.0)THEN ! Catch division by zero
      iRanPart(I,iLoop) = iRanPart(I,iLoop)/varianceiRan(I)
    ELSE
      iRanPart(I,iLoop) = 0.
    END IF ! varianceiRan(I).GT.0  
  END DO ! I = 1, 3
END DO

END SUBROUTINE BuildTransGaussNums


PPURE REAL FUNCTION CalcXiElec(Telec, iSpec)
!===================================================================================================================================
!> Calculation of the electronic degree of freedom for a given temperature and species
!===================================================================================================================================
! MODULES
USE MOD_DSMC_Vars               ,ONLY: SpecDSMC
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                :: Telec  !
INTEGER, INTENT(IN)             :: iSpec      ! Number of Species
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
INTEGER                         :: iQua
REAL                            :: TempRatio, SumOne, SumTwo
!===================================================================================================================================

SumOne = 0.0
SumTwo = 0.0

DO iQua = 0, SpecDSMC(iSpec)%MaxElecQuant-1
  TempRatio = SpecDSMC(iSpec)%ElectronicState(2,iQua)/Telec
  IF(CHECKEXP(TempRatio)) THEN
    SumOne = SumOne + SpecDSMC(iSpec)%ElectronicState(1,iQua)*SpecDSMC(iSpec)%ElectronicState(2,iQua)*EXP(-TempRatio)
    SumTwo = SumTwo + SpecDSMC(iSpec)%ElectronicState(1,iQua)*EXP(-TempRatio)
  END IF
END DO

IF((SumOne.GT.0.0).AND.(SumTwo.GT.0.0)) THEN
  CalcXiElec = 2. * SumOne / (SumTwo * Telec)
ELSE
  CalcXiElec = 0.0
END IF

RETURN

END FUNCTION CalcXiElec


!===================================================================================================================================
!> Check whether particle host element ID is on the current proc
!===================================================================================================================================
PPURE LOGICAL FUNCTION ParticleOnProc(PartID) RESULT(L)
! MODULES
USE MOD_Preproc
USE MOD_Particle_Vars ,ONLY: PEM
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN) :: PartID ! Particle index
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
!===================================================================================================================================
L = (PEM%LocalElemID(PartID).GE.1).AND.(PEM%LocalElemID(PartID).LE.PP_nElems)
END FUNCTION ParticleOnProc


END MODULE MOD_part_tools
