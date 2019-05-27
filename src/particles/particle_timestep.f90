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

MODULE MOD_Particle_VarTimeStep
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
PUBLIC :: VarTimeStep_Init, CalcVarTimeStep, VarTimeStep_CalcElemFacs, VarTimeStep_InitDistribution!, VarTimeStep_SmoothDistribution
PUBLIC :: DefineParametersVaribleTimeStep
!===================================================================================================================================

CONTAINS

!==================================================================================================================================
!> Define parameters for particles
!==================================================================================================================================
SUBROUTINE DefineParametersVaribleTimeStep()
! MODULES
USE MOD_ReadInTools ,ONLY: prms,addStrListEntry
IMPLICIT NONE
!==================================================================================================================================

CALL prms%SetSection("Variable Timestep")
CALL prms%CreateLogicalOption('Part-VariableTimeStep', 'TODO-DEFINE-PARAMETER', '.FALSE.')
! Distribution
CALL prms%CreateLogicalOption('Part-VariableTimeStep-Distribution'                 , 'TODO-DEFINE-PARAMETER', '.FALSE.')
CALL prms%CreateLogicalOption('Part-VariableTimeStep-Distribution-Adapt'                 , 'TODO-DEFINE-PARAMETER', '.FALSE.')
CALL prms%CreateRealOption(   'Part-VariableTimeStep-Distribution-TargetMCSoverMFP'  &
                            , 'TODO-DEFINE-PARAMETER')
CALL prms%CreateRealOption(   'Part-VariableTimeStep-Distribution-TargetMaxCollProb'  &
                            , 'TODO-DEFINE-PARAMETER')
CALL prms%CreateRealOption(   'Part-VariableTimeStep-Distribution-MaxFactor'  &
                            , 'Maximal time factor to avoid too large time steps and problems with halo region/particle cloning')
CALL prms%CreateRealOption(   'Part-VariableTimeStep-Distribution-MinFactor'  &
                            , 'TODO-DEFINE-PARAMETER')
CALL prms%CreateIntOption(    'Part-VariableTimeStep-Distribution-MinPartNum'  &
                            , 'Optional: Increase number of particles by decreasing the time step',  '0')
! Linear Scaling
CALL prms%CreateLogicalOption('Part-VariableTimeStep-LinearScaling'                 , 'TODO-DEFINE-PARAMETER', '.FALSE.')
CALL prms%CreateRealOption(   'Part-VariableTimeStep-ScaleFactor'  &
                            , 'TODO-DEFINE-PARAMETER')
! 2D: Radial and axial scaling towards 
CALL prms%CreateLogicalOption('Part-VariableTimeStep-Use2DFunction'                 , 'TODO-DEFINE-PARAMETER', '.FALSE.')
CALL prms%CreateRealOption(   'Part-VariableTimeStep-StagnationPoint'  &
                            , 'TODO-DEFINE-PARAMETER')
CALL prms%CreateRealOption(   'Part-VariableTimeStep-ScaleFactor2DFront'  &
                            , 'FRONT: Time step decreases towards the stagnation point')
CALL prms%CreateRealOption(   'Part-VariableTimeStep-ScaleFactor2DBack'  &
                            , 'BACK: Time step increases away from the stagnation points')
! 3D: Scaling along a given vector
CALL prms%CreateRealArrayOption('Part-VariableTimeStep-Direction'  &
                                , 'Direction of the vector along which a linear increase is applied to the time step. '//&
                                  'Currently only scaling along the x-axis (positive or negative direction) is allowed, '//&
                                  'e.g. (/-1.0,0.0,0.0/)')
CALL prms%CreateRealArrayOption('Part-VariableTimeStep-StartPoint', 'Starting point of the vector.')
CALL prms%CreateRealArrayOption('Part-VariableTimeStep-EndPoint'  , 'End point of the vector, to use the domain border: -99999.')

END SUBROUTINE DefineParametersVaribleTimeStep


SUBROUTINE VarTimeStep_Init()
!===================================================================================================================================
!> Initialization of the variable time step
!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_ReadInTools             ,ONLY: GETLOGICAL, GETINT, GETREAL, GETREALARRAY
USE MOD_Particle_Vars           ,ONLY: Symmetry2D, VarTimeStep
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! LOCAL VARIABLES
!===================================================================================================================================

SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)') ' INIT VARIABLE TIME STEP...'

VarTimeStep%UseLinearScaling = GETLOGICAL('Part-VariableTimeStep-LinearScaling','.FALSE.')
VarTimeStep%UseDistribution = GETLOGICAL('Part-VariableTimeStep-Distribution','.FALSE.')

IF(VarTimeStep%UseLinearScaling) THEN
  IF(VarTimeStep%UseDistribution) CALL abort(__STAMP__, &
    'ERROR: Cannot use linear time scaling with a given distribution')
  ! Timestep is varied according to a linear function
  VarTimeStep%ScaleFac = GETREAL('Part-VariableTimeStep-ScaleFactor','1.0')
  IF(Symmetry2D) THEN
    ! Scaling the time step in x- and r-direction with the defintion of a stagnation point
    VarTimeStep%Use2DTimeFunc = GETLOGICAL('Part-VariableTimeStep-Use2DFunction','.FALSE.')
    IF(VarTimeStep%Use2DTimeFunc) THEN
      ! FRONT: Time step decreases towards the stagnation point
      ! BACK: Time step increases away from the stagnation points
      VarTimeStep%StagnationPoint = GETREAL('Part-VariableTimeStep-StagnationPoint','0.0')
      VarTimeStep%TimeScaleFac2DFront = GETREAL('Part-VariableTimeStep-ScaleFactor2DFront','1.0')
      VarTimeStep%TimeScaleFac2DBack = GETREAL('Part-VariableTimeStep-ScaleFactor2DBack','1.0')
    END IF
  ELSE
    VarTimeStep%StartPoint = GETREALARRAY('Part-VariableTimeStep-StartPoint',3)
    VarTimeStep%EndPoint = GETREALARRAY('Part-VariableTimeStep-EndPoint',3)
    VarTimeStep%Direction = GETREALARRAY('Part-VariableTimeStep-Direction',3)
    IF(ABS(VarTimeStep%Direction(1)).NE.1.0) CALL abort(&
      __STAMP__&
      ,'ERROR: Currently direction of linear time step scaling must be defined with (/1.0,0.0,0.0/)!')
  END IF
END IF
IF(VarTimeStep%UseDistribution) THEN
  ! Read-in of the maximal collision probability from the DSMC state file and calculate the appropriate time step
  ! Particle time step is utilized for this purpose, although element-wise time step is stored in VarTimeStep%ElemFacs
  ! Flag if the time step distribution should be adapted (else read-in, if array does not exist: abort)
  VarTimeStep%AdaptDistribution = GETLOGICAL('Part-VariableTimeStep-Distribution-Adapt','.FALSE.')
  VarTimeStep%TargetMCSoverMFP = GETREAL('Part-VariableTimeStep-Distribution-TargetMCSoverMFP','0.25')
  VarTimeStep%TargetMaxCollProb = GETREAL('Part-VariableTimeStep-Distribution-TargetMaxCollProb','0.8')
  ! Read of maximal time factor to avoid too large time steps and problems with halo region/particle cloning
  VarTimeStep%DistributionMaxTimeFactor = GETREAL('Part-VariableTimeStep-Distribution-MaxFactor','1.')
  VarTimeStep%DistributionMinTimeFactor = GETREAL('Part-VariableTimeStep-Distribution-MinFactor','0.001')
  ! Optional: Increase number of particles by decreasing the time step
  VarTimeStep%DistributionMinPartNum = GETINT('Part-VariableTimeStep-Distribution-MinPartNum','0')
END IF
IF((.NOT.VarTimeStep%UseLinearScaling).AND.(.NOT.VarTimeStep%UseDistribution)) THEN
  CALL abort(&
    __STAMP__&
    ,'ERROR: No variable time step method (LinearScaling, Distribution) was chosen!')
END IF
SWRITE(UNIT_StdOut,'(132("-"))')

END SUBROUTINE VarTimeStep_Init


SUBROUTINE VarTimeStep_InitDistribution()
!===================================================================================================================================
!> Calculates/determines the variable time step element-wise
!>-------------------------------------------------------------
!> Every proc does this for the whole domain, time factor is used in readMesh to determine the weight and distribute load
!> accordingly. A smoothing (min-mean filter) is performed in InitParticle, after GEO%ElemToNeighElems are determined. If you want
!> to perform the smoothing at this point, you would require the global neighbour elements.
!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_PreProc
USE MOD_HDF5_Input,             ONLY: OpenDataFile,CloseDataFile,DatasetExists,ReadArray
USE MOD_io_hdf5
USE MOD_Mesh_Vars,              ONLY: nGlobalElems
USE MOD_PARTICLE_Vars,          ONLY: VarTimeStep, Symmetry2D, nSpecies
USE MOD_Restart_Vars,           ONLY: DoRestart, RestartFile
USE MOD_Particle_MPI_Vars      ,ONLY: PartMPI
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! LOCAL VARIABLES
INTEGER                           :: iElem
LOGICAL                           :: TimeStepExists, QualityExists, TimeStepModified
REAL, ALLOCATABLE                 :: DSMCQualityFactors(:,:), PartNum(:,:)
REAL                              :: TimeFracTemp
!===================================================================================================================================

SWRITE(UNIT_stdOut,'(A)') ' INIT VARIABLE TIME STEP DISTRIBUTION...'

TimeStepExists = .FALSE.
QualityExists = .FALSE.

! Allocate the array for the element-wise time step factor
ALLOCATE(VarTimeStep%ElemFac(nGlobalElems))
VarTimeStep%ElemFac = 1.0
#ifdef MPI
! Allocate the array for the element-wise weighting factor
ALLOCATE(VarTimeStep%ElemWeight(nGlobalElems))
VarTimeStep%ElemWeight = 1.0
#endif

IF(DoRestart) THEN
! Try to get the time step factor distribution directly from state file
  CALL OpenDataFile(TRIM(RestartFile),create=.FALSE.,single=.FALSE.,readOnly=.TRUE.,communicatorOpt=PartMPI%COMM)
  CALL DatasetExists(File_ID,'PartTimeStep',TimeStepExists)
  IF(TimeStepExists) THEN
    ASSOCIATE(nGlobalElems    => INT(nGlobalElems,IK))
      CALL ReadArray('PartTimeStep',2,(/nGlobalElems, 1_IK/),0_IK,1,RealArray=VarTimeStep%ElemFac(1:nGlobalElems))
    END ASSOCIATE
    SWRITE(UNIT_stdOut,*)'Variable Time Step: Read-in of timestep distribution from state file.'
  ELSEIF(.NOT.VarTimeStep%AdaptDistribution) THEN
    CALL abort(__STAMP__, &
      'ERROR: Variable time step requires a given timestep distribution or -Distribution-Adapt=T!')
  END IF
  CALL CloseDataFile()
ELSE
  IF(.NOT.VarTimeStep%AdaptDistribution) THEN
    SWRITE(UNIT_stdOut,'(A)') '| Variable Time Step: No restart and no adaption of time step distribution selected.'
    SWRITE(UNIT_stdOut,'(A)') '| Variable Time Step: Time step distribution is initialized uniformly with 1.'
  END IF
END IF

! WORK IN PROGRESS
! IF(VarTimeStep%AdaptDistribution) THEN
!   IF(TRIM(MacroRestartFileName).EQ.'no-file-given') THEN
!     CALL abort(__STAMP__,&
!     'ERROR: No filename for your fancy time travelling unicorn restart defined!')
!   END IF
!   SWRITE(UNIT_stdOut,'(A)') &
!     ' | Variable Time Step: Adapting the time step according to quality factors in the given DSMC state file.'
!   IF((.NOT.DoMacroscopicRestart).OR.(.NOT.DoRestart)) THEN
!     CALL abort(__STAMP__,&
!     'ERROR: It is required to use a restart and macrorestart when adapting the time step distribution!')
!   END IF
!   ! Open DSMC state file
! #ifdef MPI
!   CALL OpenDataFile(MacroRestartFileName,create=.FALSE.,single=.FALSE.)
! #else
!   CALL OpenDataFile(MacroRestartFileName,create=.FALSE.)
! #endif
!   ! Read-in of DSMC quality factors to calculate the required timestep for particle time step
!   ! 1: MaxCollProb, 2: MeanCollProb, 3: MCSoverMFP
!   ALLOCATE(DSMCQualityFactors(nGlobalElems,1:3))
!   DSMCQualityFactors = 0.
!   CALL DatasetExists(File_ID,'DSMC_quality',QualityExists)
!   IF(QualityExists) THEN
!     CALL ReadArray('DSMC_quality',2,(/nGlobalElems, 3/),0,1,RealArray=DSMCQualityFactors(1:nGlobalElems,1:3))
!   ELSE
!     CALL abort(__STAMP__, &
!     'ERROR: Variable time step using a distribution requires quality factors within the DSMC state!')
!   END IF
!   ! Get the particle numbers per cell
!   ALLOCATE(PartNum(nGlobalElems,nSpecies+1))
!   CALL ReadArray('DSMC_partnum',2,(/nGlobalElems,nSpecies+1/),0,1,RealArray=PartNum(1:nGlobalElems,1:nSpecies+1))
!   ! Calculating the time step per element based on the read-in max collision prob and mean collision separation
!   DO iElem = 1, nGlobalElems
!     TimeStepModified = .FALSE.
!     ! Skipping cells, where less than 2 particles were sampled
!     IF(PartNum(iElem,nSpecies+1).LT.2.0) CYCLE
! #ifdef MPI
!     ! Storing the old time step factor temporarily
!     VarTimeStep%ElemWeight(iElem) = VarTimeStep%ElemFac(iElem)
! #endif
!     ! Storing either a 1 or the read-in time step factor in a temporary variable
!     TimeFracTemp = VarTimeStep%ElemFac(iElem)
!     ! Adapting the time step in order to achieve MaxCollProb < 0.8
!     IF(DSMCQualityFactors(iElem,1).GT.VarTimeStep%TargetMaxCollProb) THEN
!       TimeFracTemp = VarTimeStep%TargetMaxCollProb*VarTimeStep%ElemFac(iElem) / DSMCQualityFactors(iElem,1)
!       TimeStepModified = .TRUE.
!     END IF
!     ! Adapting the time step in order to reduce the mean collision separation
!     IF(DSMCQualityFactors(iElem,3).GT.VarTimeStep%TargetMCSoverMFP) THEN
!       IF(Symmetry2D) THEN
!         TimeFracTemp = MIN(TimeFracTemp,VarTimeStep%ElemFac(iElem)*(VarTimeStep%TargetMCSoverMFP/DSMCQualityFactors(iElem,3))**2)
!       ELSE
!         TimeFracTemp = MIN(TimeFracTemp,VarTimeStep%ElemFac(iElem)*(VarTimeStep%TargetMCSoverMFP/DSMCQualityFactors(iElem,3))**3)
!       END IF
!       TimeStepModified = .TRUE.
!     END IF
!     ! Decrease time step according to a given minimal particle number (optional: default is 0)
!     IF(VarTimeStep%DistributionMinPartNum.GT.0) THEN
!       IF(PartNum(iElem,nSpecies+1).LT.VarTimeStep%DistributionMinPartNum) THEN
!         TimeFracTemp = MIN(TimeFracTemp,PartNum(iElem,nSpecies+1)/VarTimeStep%DistributionMinPartNum*VarTimeStep%ElemFac(iElem))
!         TimeStepModified = .TRUE.
!       END IF
!     END IF
!     ! Limiting the minimal time step factor to the given value
!     TimeFracTemp = MAX(TimeFracTemp,VarTimeStep%DistributionMinTimeFactor)
!     ! If time step was not adapted due to particle number, collision probability or mean collision separation
!     ! Choose appropriate time step to satisfy target MCSoverMFP, MaxCollProb and MinPartNum
!     IF(.NOT.TimeStepModified) THEN
!       TimeFracTemp = MIN(VarTimeStep%TargetMaxCollProb*VarTimeStep%ElemFac(iElem) / DSMCQualityFactors(iElem,1),  &
!                          PartNum(iElem,nSpecies+1)/VarTimeStep%DistributionMinPartNum*VarTimeStep%ElemFac(iElem))
!       IF(DSMCQualityFactors(iElem,3).GT.0.0) THEN
!         IF(Symmetry2D) THEN
!           TimeFracTemp = MIN(TimeFracTemp,VarTimeStep%ElemFac(iElem)*(VarTimeStep%TargetMCSoverMFP/DSMCQualityFactors(iElem,3))**2)
!         ELSE
!           TimeFracTemp = MIN(TimeFracTemp,VarTimeStep%ElemFac(iElem)*(VarTimeStep%TargetMCSoverMFP/DSMCQualityFactors(iElem,3))**3)
!         END IF
!       END IF
!     END IF
!     ! Finally, limiting the maximal time step factor to the given value and saving it to the right variable
!     VarTimeStep%ElemFac(iElem) = MIN(TimeFracTemp,VarTimeStep%DistributionMaxTimeFactor)
! #ifdef MPI
!     ! Calculating the weight, multiplied with the particle number from state file during readMesh
!     ! (covering the case when a time step distribution is read-in and adapted -> elements have been already once load-balanced with
!     ! the old time step, consequently weight should only include difference between old and new time step)
!     VarTimeStep%ElemWeight(iElem) = VarTimeStep%ElemWeight(iElem) / VarTimeStep%ElemFac(iElem)
! #endif
!   END DO
!   ! Close the DSMC state file and deallocate not required variables
!   CALL CloseDataFile()
!   SDEALLOCATE(DSMCQualityFactors)
!   SDEALLOCATE(PartNum)
! END IF      ! Adapt Distribution

SWRITE(UNIT_StdOut,'(132("-"))')

END SUBROUTINE VarTimeStep_InitDistribution


REAL FUNCTION CalcVarTimeStep(xPos, yPos, iElem)
!===================================================================================================================================
! 
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_Vars,          ONLY: VarTimeStep, Symmetry2D
USE MOD_Particle_Mesh_Vars     ,ONLY: GEO
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN), OPTIONAL      :: xPos, yPos
INTEGER, INTENT(IN), OPTIONAL   :: iElem
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
REAL          :: xFactor
!===================================================================================================================================

  CalcVarTimeStep = 1.

  IF(VarTimeStep%UseLinearScaling) THEN
    IF(Symmetry2D) THEN
      IF (VarTimeStep%Use2DTimeFunc) THEN
        IF(.NOT.PRESENT(xPos).OR..NOT.PRESENT(yPos)) CALL abort(__STAMP__,&
          'ERROR: Position in x-direction is required in the call of CalcVarTimeStep for linear scaling in 2D!')
        IF (xPos.LT.VarTimeStep%StagnationPoint) THEN
          xFactor = ABS((VarTimeStep%StagnationPoint-xPos)/GEO%xminglob*VarTimeStep%TimeScaleFac2DFront)
        ELSE
          xFactor = ABS((xPos-VarTimeStep%StagnationPoint)/GEO%xmaxglob*VarTimeStep%TimeScaleFac2DBack)
        END IF
        CalcVarTimeStep = (1. + yPos/GEO%ymaxglob*VarTimeStep%ScaleFac)*(1.+xFactor)
      ELSE
        IF(.NOT.PRESENT(yPos)) CALL abort(__STAMP__,&
          'ERROR: Position in x-direction is required in the call of CalcVarTimeStep for linear scaling in 2D!')
        CalcVarTimeStep = (1. + yPos/GEO%ymaxglob*VarTimeStep%ScaleFac)
      END IF
    ELSE
      IF(.NOT.PRESENT(iElem)) CALL abort(__STAMP__,&
        'ERROR: Element number is required in the call of CalcVarTimeStep for distribution/scaling in 3D!')
      CalcVarTimeStep = VarTimeStep%ElemFac(iElem)
    END IF
  ELSE IF(VarTimeStep%UseDistribution) THEN
    IF(.NOT.PRESENT(iElem)) CALL abort(__STAMP__,&
      'ERROR: Element number is required in the call of CalcVarTimeStep for distribution!')
    CalcVarTimeStep = VarTimeStep%ElemFac(iElem)
  ELSE
    CALL abort(__STAMP__,&
      'ERROR: CalcVarTimeStep should not be utilized without LinearScaling/Distribution flag!')
  END IF

  RETURN

END FUNCTION CalcVarTimeStep


SUBROUTINE VarTimeStep_CalcElemFacs()
!===================================================================================================================================
!> Calculates/determines the variable time step element-wise (every proc for his own domain)
!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Particle_Vars          ,ONLY: VarTimeStep
USE MOD_Particle_Mesh_Vars     ,ONLY: GEO
USE MOD_Mesh_Vars              ,ONLY: nElems
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! LOCAL VARIABLES
INTEGER                   :: iElem
!===================================================================================================================================

ALLOCATE(VarTimeStep%ElemFac(nElems))
VarTimeStep%ElemFac = 1.0
IF (VarTimeStep%Direction(1).GT.0.0) THEN
  DO iElem = 1, nElems
    IF (GEO%ElemMidPoint(1,iElem).LT.VarTimeStep%StartPoint(1)) THEN
      VarTimeStep%ElemFac(iElem)=1.0
    ELSE IF (VarTimeStep%EndPoint(1).EQ.-99999.) THEN
      VarTimeStep%ElemFac(iElem)= 1.0 + (VarTimeStep%ScaleFac-1.0)/(GEO%xmaxglob-VarTimeStep%StartPoint(1)) &
          * (GEO%ElemMidPoint(1,iElem)-VarTimeStep%StartPoint(1))
    ELSE 
      IF (GEO%ElemMidPoint(1,iElem).GT.VarTimeStep%EndPoint(1)) THEN
        VarTimeStep%ElemFac(iElem)=VarTimeStep%ScaleFac
      ELSE
        VarTimeStep%ElemFac(iElem)= 1.0 + (VarTimeStep%ScaleFac-1.0)/(VarTimeStep%EndPoint(1)-VarTimeStep%StartPoint(1)) &
            * (GEO%ElemMidPoint(1,iElem)-VarTimeStep%StartPoint(1))
      END IF
    END IF
  END DO
ELSE
  DO iElem = 1, nElems
    IF (GEO%ElemMidPoint(1,iElem).GT.VarTimeStep%StartPoint(1)) THEN
      VarTimeStep%ElemFac(iElem)=1.0
    ELSE IF (VarTimeStep%EndPoint(1).EQ.-99999.) THEN
      VarTimeStep%ElemFac(iElem)= 1.0 + (VarTimeStep%ScaleFac-1.0)/(VarTimeStep%StartPoint(1)-GEO%xminglob) &
          * (VarTimeStep%StartPoint(1)-GEO%ElemMidPoint(1,iElem))
    ELSE 
      IF (GEO%ElemMidPoint(1,iElem).LT.VarTimeStep%EndPoint(1)) THEN
        VarTimeStep%ElemFac(iElem)=VarTimeStep%ScaleFac
      ELSE
        VarTimeStep%ElemFac(iElem)= 1.0 + (VarTimeStep%ScaleFac-1.0)/(VarTimeStep%StartPoint(1)-VarTimeStep%EndPoint(1)) &
            * (VarTimeStep%StartPoint(1)-GEO%ElemMidPoint(1,iElem))
      END IF
    END IF
  END DO
END IF

END SUBROUTINE VarTimeStep_CalcElemFacs


! SUBROUTINE VarTimeStep_SmoothDistribution(onlyMPIExchange)
! !===================================================================================================================================
! ! 
! !===================================================================================================================================
! ! MODULES
! USE MOD_Particle_Vars           ,ONLY: VarTimeStep
! USE MOD_Particle_Mesh_Vars      ,ONLY: GEO
! USE MOD_Mesh_Vars               ,ONLY: nElems
! USE MOD_Globals
! #ifdef MPI
! USE MOD_part_MPI_Vars           ,ONLY: MPIGEO, PMPIVAR
! #endif
! ! IMPLICIT VARIABLE HANDLING
! IMPLICIT NONE
! !-----------------------------------------------------------------------------------------------------------------------------------
! ! INPUT VARIABLES
! LOGICAL, OPTIONAL,INTENT(IN)    :: onlyMPIExchange
! !-----------------------------------------------------------------------------------------------------------------------------------
! ! OUTPUT VARIABLES
! !-----------------------------------------------------------------------------------------------------------------------------------
! ! LOCAL VARIABLES
! INTEGER                               :: iElem, jElem, ElemID
! REAL                                  :: tempFact(nElems), tempMean(30), NumTotalElems
! ! Filters
! REAL                                  :: MeanTimeFactor
! #ifdef MPI
! INTEGER                               :: iProc
! REAL, ALLOCATABLE                     :: MPIElemFac(:)
! TYPE tTempArrayProc
!   REAL, ALLOCATABLE                   :: SendMsg(:)
!   REAL, ALLOCATABLE                   :: RecvMsg(:)
! END TYPE
! TYPE(tTempArrayProc), ALLOCATABLE     :: TempArrayProc(:)
! !===================================================================================================================================
! ALLOCATE(TempArrayProc(0:PMPIVAR%nProcs-1))
! ALLOCATE(MPIElemFac(1:SIZE(MPIGEO%ElemMPIID,1)))
! MPIElemFac = 1.0

! DO iProc = 0, PMPIVAR%nProcs-1
!   IF (PMPIVAR%iProc.NE.iProc) THEN
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems.GT.0) THEN
!       ALLOCATE(TempArrayProc(iProc)%SendMsg(MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems))
!       DO iElem = 1, MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems
!         TempArrayProc(iProc)%SendMsg(iElem) & 
!           = VarTimeStep%ElemFac(MPIGEO%MPIElemsToCommunicate(iProc)%SendElems(iElem))
!       END DO
!     END IF
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems.GT.0) THEN
!       ALLOCATE(TempArrayProc(iProc)%RecvMsg(MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems))
!     END IF
!   END IF
! END DO

! ! send/recv message length
! DO iProc=0, PMPIVAR%nProcs-1
!   IF (PMPIVAR%iProc.LT.iProc) THEN
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems.GT.0) THEN
!       CALL MPI_SEND(TempArrayProc(iProc)%SendMsg,MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems &
!           ,MPI_DOUBLE_PRECISION,iProc,1101,PMPIVAR%COMM,IERROR)
!     END IF
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems.GT.0) THEN
!       CALL MPI_RECV(TempArrayProc(iProc)%RecvMsg,MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems &
!           ,MPI_DOUBLE_PRECISION,iProc,1101,PMPIVAR%COMM,MPISTATUS,IERROR)
!     END IF
!   ELSE IF (PMPIVAR%iProc.GT.iProc) THEN
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems.GT.0) THEN
!       CALL MPI_RECV(TempArrayProc(iProc)%RecvMsg,MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems &
!           ,MPI_DOUBLE_PRECISION,iProc,1101,PMPIVAR%COMM,MPISTATUS,IERROR)
!     END IF
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems.GT.0) THEN
!       CALL MPI_SEND(TempArrayProc(iProc)%SendMsg,MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems &
!           ,MPI_DOUBLE_PRECISION,iProc,1101,PMPIVAR%COMM,IERROR)
!     END IF
!   END IF
! END DO 

! ! Sort recv message
! MPIElemFac = 0.0
! DO iProc=0, PMPIVAR%nProcs-1
!   IF (PMPIVAR%iProc.NE.iProc) THEN
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems.GT.0) THEN
!       DO iElem = 1, MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems
!         MPIElemFac(MPIGEO%MPIElemsToCommunicate(iProc)%RecvElems(iElem)) &
!           = TempArrayProc(iProc)%RecvMsg(iElem)
!       END DO 
!     END IF
!   END IF
! END DO
! DEALLOCATE(TempArrayProc)  
! #endif

! IF (PRESENT(onlyMPIExchange)) RETURN
! ! --------- min filter
! tempFact(1:nElems) = VarTimeStep%ElemFac(1:nElems)
! DO iElem =1, nElems
!   tempMean(1) = tempFact(iElem)
!   NumTotalElems = 1.
!   DO jElem = 1, GEO%NumNeighborElems(iElem)
!     ElemID = GEO%ElemToNeighElems(iElem)%ElemID(jElem)
!     tempMean(1+jElem) = tempFact(ElemID)
!     NumTotalElems = NumTotalElems + 1.
!   END DO
! #ifdef MPI
!   DO jElem = 1, MPIGEO%NumNeighborElems(iElem)
!     ElemID = MPIGEO%ElemToNeighElems(iElem)%ElemID(jElem)
!     tempMean(1+GEO%NumNeighborElems(iElem)+jElem) = MPIElemFac(ElemID)
!     NumTotalElems = NumTotalElems + 1.
!   END DO
! #endif
!   IF (NumTotalElems.GT.1) THEN
!     VarTimeStep%ElemFac(iELem) = MINVAL(tempMean(1:NINT(NumTotalElems)))
!   END IF
! END DO
! ! --------- communication of the values from the min filter
! #ifdef MPI
! ALLOCATE(TempArrayProc(0:PMPIVAR%nProcs-1))
! DO iProc = 0, PMPIVAR%nProcs-1
!   IF (PMPIVAR%iProc.NE.iProc) THEN
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems.GT.0) THEN
!       ALLOCATE(TempArrayProc(iProc)%SendMsg(MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems))
!       DO iElem = 1, MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems
!         TempArrayProc(iProc)%SendMsg(iElem) & 
!           = VarTimeStep%ElemFac(MPIGEO%MPIElemsToCommunicate(iProc)%SendElems(iElem))
!       END DO
!     END IF
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems.GT.0) THEN
!       ALLOCATE(TempArrayProc(iProc)%RecvMsg(MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems))
!     END IF
!   END IF
! END DO

! ! send/recv message length
! DO iProc=0, PMPIVAR%nProcs-1
!   IF (PMPIVAR%iProc.LT.iProc) THEN
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems.GT.0) THEN
!       CALL MPI_SEND(TempArrayProc(iProc)%SendMsg,MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems &
!           ,MPI_DOUBLE_PRECISION,iProc,1101,PMPIVAR%COMM,IERROR)
!     END IF
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems.GT.0) THEN
!       CALL MPI_RECV(TempArrayProc(iProc)%RecvMsg,MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems &
!           ,MPI_DOUBLE_PRECISION,iProc,1101,PMPIVAR%COMM,MPISTATUS,IERROR)
!     END IF
!   ELSE IF (PMPIVAR%iProc.GT.iProc) THEN
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems.GT.0) THEN
!       CALL MPI_RECV(TempArrayProc(iProc)%RecvMsg,MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems &
!           ,MPI_DOUBLE_PRECISION,iProc,1101,PMPIVAR%COMM,MPISTATUS,IERROR)
!     END IF
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems.GT.0) THEN
!       CALL MPI_SEND(TempArrayProc(iProc)%SendMsg,MPIGEO%MPIElemsToCommunicate(iProc)%NumSendElems &
!           ,MPI_DOUBLE_PRECISION,iProc,1101,PMPIVAR%COMM,IERROR)
!     END IF
!   END IF
! END DO 

! ! Sort recv message
! MPIElemFac = 0.0
! DO iProc=0, PMPIVAR%nProcs-1
!   IF (PMPIVAR%iProc.NE.iProc) THEN
!     IF (MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems.GT.0) THEN
!       DO iElem = 1, MPIGEO%MPIElemsToCommunicate(iProc)%NumRecvElems
!         MPIElemFac(MPIGEO%MPIElemsToCommunicate(iProc)%RecvElems(iElem)) &
!           = TempArrayProc(iProc)%RecvMsg(iElem)
!       END DO 
!     END IF
!   END IF
! END DO
! DEALLOCATE(TempArrayProc)
! #endif
! ! -----------------------
! ! --------- mean filter
! DO iElem =1, nElems
!   MeanTimeFactor = VarTimeStep%ElemFac(iElem)
!   NumTotalElems = 1.
!   DO jElem = 1, GEO%NumNeighborElems(iElem)
!     ElemID = GEO%ElemToNeighElems(iElem)%ElemID(jElem)
!     MeanTimeFactor = MeanTimeFactor + VarTimeStep%ElemFac(ElemID)
!     NumTotalElems = NumTotalElems + 1.
!   END DO
! #ifdef MPI
!   DO jElem = 1, MPIGEO%NumNeighborElems(iElem)
!     ElemID = MPIGEO%ElemToNeighElems(iElem)%ElemID(jElem)
!     MeanTimeFactor = MeanTimeFactor + MPIElemFac(ElemID)
!     NumTotalElems = NumTotalElems + 1.
!   END DO
! #endif
!   IF(NumTotalElems.GT.0.0) VarTimeStep%ElemFac(iElem) = MeanTimeFactor/NumTotalElems
! END DO

! END SUBROUTINE VarTimeStep_SmoothDistribution

END MODULE MOD_Particle_VarTimeStep
