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

MODULE MOD_Restart
!===================================================================================================================================
! Module to handle PICLas's restart
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
INTERFACE InitRestart
  MODULE PROCEDURE InitRestart
END INTERFACE

INTERFACE Restart
  MODULE PROCEDURE Restart
END INTERFACE

INTERFACE FinalizeRestart
  MODULE PROCEDURE FinalizeRestart
END INTERFACE

PUBLIC :: InitRestart,FinalizeRestart
PUBLIC :: Restart

PUBLIC :: DefineParametersRestart
!===================================================================================================================================

CONTAINS

!==================================================================================================================================
!> Define parameters.
!==================================================================================================================================
SUBROUTINE DefineParametersRestart()
! MODULES
USE MOD_ReadInTools ,ONLY: prms
IMPLICIT NONE
!==================================================================================================================================
CALL prms%SetSection("Restart")
!CALL prms%CreateLogicalOption('ResetTime', "Override solution time to t=0 on restart.", '.FALSE.')
#if USE_LOADBALANCE
CALL prms%CreateLogicalOption('DoInitialAutoRestart',&
                               "Set Flag for doing automatic initial restart with loadbalancing routines "// &
                               "after first 'InitialAutoRestartSample'-number of iterations.\n"// &
                               "Restart is done if Imbalance > 'Load-DeviationThreshold'."&
                               , '.FALSE.')
CALL prms%CreateIntOption('InitialAutoRestartSample',&
                               "Define number of iterations at simulation start used for ElemTime "// &
                               "sampling before performing automatic initial restart.\n"// &
                               "IF 0 than one iteration is sampled and statefile written has zero timeflag.\n"// &
                               " DEFAULT: LoadBalanceSample.")
CALL prms%CreateLogicalOption( 'InitialAutoRestart-PartWeightLoadBalance', &
                               "Set flag for doing initial auto restart with partMPIWeight instead of"//&
                               " ElemTimes. ElemTime array in state file is filled with nParts*PartMPIWeight for each Elem. "//&
                               " If Flag [TRUE] InitialAutoRestartSample is set to 0 and vice versa.", '.FALSE.')
#endif /*USE_LOADBALANCE*/
CALL prms%CreateLogicalOption( 'RestartNullifySolution', &
                               "Set the DG solution to zero (ignore the DG solution in the state file)",&
                               '.FALSE.')
CALL prms%CreateLogicalOption('Particles-MacroscopicRestart', &
                              "TO-DO",&
                              '.FALSE.')
CALL prms%CreateStringOption( 'Particles-MacroscopicRestart-Filename', &
                              'TO-DO')
END SUBROUTINE DefineParametersRestart


SUBROUTINE InitRestart()
!===================================================================================================================================
! Initialize all necessary information to perform the restart
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Globals_Vars       ,ONLY: FileVersionHDF5
USE MOD_PreProc
USE MOD_ReadInTools        ,ONLY: GETLOGICAL,GETSTR
#if USE_LOADBALANCE
USE MOD_ReadInTools        ,ONLY: GETINT
USE MOD_LoadBalance_Vars   ,ONLY: LoadBalanceSample
USE MOD_ReadInTools        ,ONLY: PrintOption
#endif /*USE_LOADBALANCE*/
USE MOD_Interpolation_Vars ,ONLY: xGP,InterpolationInitIsDone
USE MOD_Restart_Vars
USE MOD_HDF5_Input         ,ONLY: OpenDataFile,CloseDataFile,GetDataProps,ReadAttribute,File_ID
USE MOD_HDF5_Input         ,ONLY: DatasetExists
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
#if USE_LOADBALANCE
CHARACTER(20)               :: hilf
#endif /*USE_LOADBALANCE*/
#if USE_HDG
LOGICAL                     :: DG_SolutionUExists
#endif /*USE_HDG*/
LOGICAL                     :: FileVersionExists
!===================================================================================================================================
IF((.NOT.InterpolationInitIsDone).OR.RestartInitIsDone)THEN
   CALL abort(&
__STAMP__&
,'InitRestart not ready to be called or already called.',999,999.)
   RETURN
END IF

SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)') ' INIT RESTART...'

! Set the DG solution to zero (ignore the DG solution in the state file)
RestartNullifySolution = GETLOGICAL('RestartNullifySolution','F')

! Macroscopic restart
DoMacroscopicRestart = GETLOGICAL('Particles-MacroscopicRestart')
IF(DoMacroscopicRestart) MacroRestartFileName = GETSTR('Particles-MacroscopicRestart-Filename')

! Check if we want to perform a restart
IF (LEN_TRIM(RestartFile).GT.0) THEN
  ! Read in the state file we want to restart from
  DoRestart = .TRUE.
  CALL OpenDataFile(RestartFile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.,communicatorOpt=MPI_COMM_WORLD)
#ifdef PP_POIS
#if (PP_nVar==8)
  !The following arrays are read from the file
  !CALL ReadArray('DG_SolutionE',5,(/PP_nVar,PP_N+1,PP_N+1,PP_N+1,PP_nElems/),OffsetElem,5,RealArray=U)
  !CALL ReadArray('DG_SolutionPhi',5,(/4,PP_N+1,PP_N+1,PP_N+1,PP_nElems/),OffsetElem,5,RealArray=Phi)
  CALL abort(&
      __STAMP__&
      ,'InitRestart: This case is not implemented here. Fix this!')
#else
  !The following arrays are read from the file
  !CALL ReadArray('DG_SolutionE',5,(/PP_nVar,PP_N+1,PP_N+1,PP_N+1,PP_nElems/),OffsetElem,5,RealArray=U)
  !CALL ReadArray('DG_SolutionPhi',5,(/PP_nVar,PP_N+1,PP_N+1,PP_N+1,PP_nElems/),OffsetElem,5,RealArray=Phi)
  CALL abort(&
      __STAMP__&
      ,'InitRestart: This case is not implemented here. Fix this!')
#endif
#elif USE_HDG
  CALL DatasetExists(File_ID,'DG_SolutionU',DG_SolutionUExists)
  IF(DG_SolutionUExists)THEN
    CALL GetDataProps('DG_SolutionU',nVar_Restart,N_Restart,nElems_Restart,NodeType_Restart)
  END IF
#else
  CALL GetDataProps('DG_Solution',nVar_Restart,N_Restart,nElems_Restart,NodeType_Restart)
#endif
  IF(RestartNullifySolution)THEN ! Open the restart file and neglect the DG solution (only read particles if present)
    SWRITE(UNIT_stdOut,*)' | Restarting from File: "',TRIM(RestartFile),'" (but without reading the DG solution)'
  ELSE ! Use the solution in the restart file
    SWRITE(UNIT_stdOut,*)' | Restarting from File: "',TRIM(RestartFile),'"'
    IF(PP_nVar.NE.nVar_Restart)THEN
      SWRITE(UNIT_StdOut,'(A,I5)')"     PP_nVar =", PP_nVar
      SWRITE(UNIT_StdOut,'(A,I5)')"nVar_Restart =", nVar_Restart
      CALL abort(&
          __STAMP__&
          ,'InitRestart: PP_nVar.NE.nVar_Restart (number of variables in restat file does no match the compiled equation system).')
    END IF
  END IF
  ! Read in time from restart file
  CALL ReadAttribute(File_ID,'Time',1,RealScalar=RestartTime)
  ! check file version
  CALL DatasetExists(File_ID,'File_Version',FileVersionExists,attrib=.TRUE.)
  IF (FileVersionExists) THEN
    CALL ReadAttribute(File_ID,'File_Version',1,RealScalar=FileVersionHDF5)
  ELSE
    CALL abort(&
        __STAMP__&
        ,'Error in InitRestart(): Attribute "File_Version" does not exist!')
  END IF
  IF(FileVersionHDF5.LT.1.5)THEN
    SWRITE(UNIT_StdOut,'(A)')' '
    SWRITE(UNIT_StdOut,'(A)')' %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% '
    SWRITE(UNIT_StdOut,'(A)')' '
    SWRITE(UNIT_StdOut,'(A)')' Restart file is too old! "File_Version" in restart file < 1.5!'
    SWRITE(UNIT_StdOut,'(A)')' The format used in the restart file is not compatible with this version of PICLas.'
    SWRITE(UNIT_StdOut,'(A)')' Among others, the particle format (PartData) has changed.'
    SWRITE(UNIT_StdOut,'(A)')' Run python script '
    SWRITE(UNIT_StdOut,'(A)')' '
    SWRITE(UNIT_StdOut,'(A)')'     python  ./tools/flip_PartState/flip_PartState.py  --help'
    SWRITE(UNIT_StdOut,'(A)')' '
    SWRITE(UNIT_StdOut,'(A)')' for info regarding the usage and run the script against the restart file, e.g., '
    SWRITE(UNIT_StdOut,'(A)')' '
    SWRITE(UNIT_StdOut,'(A)')'     python  ./tools/flip_PartState/flip_PartState.py  ProjectName_State_000.0000xxxxxx.h5'
    SWRITE(UNIT_StdOut,'(A)')' '
    SWRITE(UNIT_StdOut,'(A)')' to update the format and file version number.'
    SWRITE(UNIT_StdOut,'(A)')' Note that the format can be changed back to the old one by running the script a second time.'
    SWRITE(UNIT_StdOut,'(A)')' '
    SWRITE(UNIT_StdOut,'(A)')' %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% '
    CALL abort(&
    __STAMP__&
    ,'Error in InitRestart(): "File_Version" in restart file < 1.5. See error message above to fix. File version in restart file =',&
    RealInfoOpt=FileVersionHDF5)
  END IF ! FileVersionHDF5.LT.1.5
  CALL CloseDataFile()
ELSE
  RestartTime = 0.
  SWRITE(UNIT_StdOut,'(A)')' | No restart wanted, doing a fresh computation!'
END IF

! Automatically do a load balance step at the beginning of a new simulation or a user-restarted simulation
#if USE_LOADBALANCE
DoInitialAutoRestart = GETLOGICAL('DoInitialAutoRestart')
IF(nProcessors.LT.2) DoInitialAutoRestart = .FALSE.
WRITE(UNIT=hilf,FMT='(I0)') LoadBalanceSample
InitialAutoRestartSample = GETINT('InitialAutoRestartSample',TRIM(hilf))
IAR_PerformPartWeightLB = GETLOGICAL('InitialAutoRestart-PartWeightLoadBalance','F')
IF (IAR_PerformPartWeightLB) THEN
  InitialAutoRestartSample = 0 ! deactivate loadbalance sampling of ElemTimes if balancing with partweight is enabled
  CALL PrintOption('InitialAutoRestart-PartWeightLoadBalance = T : InitialAutoRestartSample','INFO',IntOpt=InitialAutoRestartSample)
ELSE IF (InitialAutoRestartSample.EQ.0) THEN
  IAR_PerformPartWeightLB = .TRUE. ! loadbalance (ElemTimes) is done with partmpiweight if loadbalancesampling is set to zero
  CALL PrintOption('InitialAutoRestart-PartWeightLoadBalance','INFO',LogOpt=IAR_PerformPartWeightLB)
END IF
#endif /*USE_LOADBALANCE*/

! Set wall time to the beginning of the simulation or when a restart is performed to the current wall time
RestartWallTime=PICLASTIME()

IF(DoRestart .AND. (N_Restart .NE. PP_N))THEN
  BuildNewMesh       =.TRUE.
  WriteNewMesh       =.TRUE.
  InterpolateSolution=.TRUE.
END IF

IF(InterpolateSolution)THEN
  CALL initRestartBasis(PP_N,N_Restart,xGP)
END IF

RestartInitIsDone = .TRUE.
SWRITE(UNIT_stdOut,'(A)')' INIT RESTART DONE!'
SWRITE(UNIT_StdOut,'(132("-"))')
END SUBROUTINE InitRestart



SUBROUTINE InitRestartBasis(N_in,N_Restart_in,xGP)
!===================================================================================================================================
! Initialize all necessary information to perform the restart
!===================================================================================================================================
! MODULES
USE MOD_Restart_Vars, ONLY:Vdm_GaussNRestart_GaussN
USE MOD_Basis,        ONLY:LegendreGaussNodesAndWeights,LegGaussLobNodesAndWeights,ChebyGaussLobNodesAndWeights
USE MOD_Basis,        ONLY:BarycentricWeights,InitializeVandermonde
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(IN)                  :: N_in,N_Restart_in
REAL,INTENT(IN),DIMENSION(0:N_in)   :: xGP
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,DIMENSION(0:N_Restart_in)  :: xGP_Restart,wBary_Restart
!===================================================================================================================================
  ALLOCATE(Vdm_GaussNRestart_GaussN(0:N_in,0:N_Restart_in))
#if (PP_NodeType==1)
  CALL LegendreGaussNodesAndWeights(N_Restart_in,xGP_Restart)
#elif (PP_NodeType==2)
  CALL LegGaussLobNodesAndWeights(N_Restart_in,xGP_Restart)
#elif (PP_NodeType==3)
  CALL ChebyGaussLobNodesAndWeights(N_Restart_in,xGP_Restart)
#endif
  CALL BarycentricWeights(N_Restart_in,xGP_Restart,wBary_Restart)
  CALL InitializeVandermonde(N_Restart_in,N_in,wBary_Restart,xGP_Restart,xGP,Vdm_GaussNRestart_GaussN)
END SUBROUTINE InitRestartBasis



SUBROUTINE Restart()
!===================================================================================================================================
! Read in mesh (if available) and state, set time for restart
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_IO_HDF5
USE MOD_DG_Vars                ,ONLY: U
USE MOD_Mesh_Vars              ,ONLY: OffsetElem
#if USE_HDG
USE MOD_Mesh_Vars              ,ONLY: nSides
#endif
USE MOD_Restart_Vars           ,ONLY: DoRestart,N_Restart,RestartFile,RestartTime,InterpolateSolution,RestartNullifySolution
USE MOD_ChangeBasis            ,ONLY: ChangeBasis3D
USE MOD_HDF5_input             ,ONLY: OpenDataFile,CloseDataFile,ReadArray,ReadAttribute,GetDataSize
USE MOD_HDF5_Output            ,ONLY: FlushHDF5
#if ! (USE_HDG)
USE MOD_PML_Vars               ,ONLY: DoPML,PMLToElem,U2,nPMLElems,PMLnVar
USE MOD_Restart_Vars           ,ONLY: Vdm_GaussNRestart_GaussN
#endif /*not USE_HDG*/
#ifdef PP_POIS
USE MOD_Equation_Vars          ,ONLY: Phi
#endif /*PP_POIS*/
#ifdef PARTICLES
USE MOD_Restart_Tools          ,ONLY: ReadNodeSourceExtFromHDF5
USE MOD_Restart_Vars           ,ONLY: DoMacroscopicRestart
USE MOD_Particle_Vars          ,ONLY: PartState, PartSpecies, PEM, PDM, nSpecies, usevMPF, PartMPF,PartPosRef, SpecReset, Species
USE MOD_part_tools             ,ONLY: UpdateNextFreePosition,StoreLostParticleProperties
USE MOD_DSMC_Vars              ,ONLY: UseDSMC,CollisMode,PartStateIntEn,DSMC,VibQuantsPar,PolyatomMolDSMC,SpecDSMC,RadialWeighting
USE MOD_DSMC_Vars              ,ONLY: ElectronicDistriPart, AmbipolElecVelo
USE MOD_Eval_XYZ               ,ONLY: GetPositionInRefElem
USE MOD_Particle_Localization  ,ONLY: LocateParticleInElement
USE MOD_Particle_Mesh_Tools    ,ONLY: ParticleInsideQuad3D
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemEpsOneCell
USE MOD_Particle_Tracking_Vars ,ONLY: TrackingMethod,NbrOfLostParticles, NbrOfLostParticlesTotal
#if !(USE_MPI)
USE MOD_Particle_Tracking_Vars ,ONLY: CountNbrOfLostParts
#endif /*!(USE_MPI)*/
#if USE_MPI
USE MOD_Particle_MPI_Vars      ,ONLY: PartMPI
#endif /*USE_MPI*/
USE MOD_PICDepo_Vars           ,ONLY: DoDeposition, RelaxDeposition, PartSourceOld
USE MOD_Dielectric_Vars        ,ONLY: DoDielectricSurfaceCharge
#endif /*PARTICLES*/
#if USE_HDG
USE MOD_HDG_Vars               ,ONLY: lambda, nGP_face
USE MOD_HDG                    ,ONLY: RestartHDG
USE MOD_Mesh_Vars              ,ONLY: GlobalUniqueSideID,MortarType,SideToElem
USE MOD_StringTools            ,ONLY: set_formatting,clear_formatting
USE MOD_Mappings               ,ONLY: CGNS_SideToVol2
USE MOD_Mesh_Vars              ,ONLY: firstMortarInnerSide,lastMortarInnerSide,MortarInfo
USE MOD_Mesh_Vars              ,ONLY: lastMPISide_MINE
#if USE_MPI
USE MOD_MPI_Vars               ,ONLY: RecRequest_U,SendRequest_U
USE MOD_MPI                    ,ONLY: StartReceiveMPIData,StartSendMPIData,FinishExchangeMPIData
#endif /*USE_MPI*/
#endif /*USE_HDG*/
#if defined(PARTICLES) || (USE_HDG)
USE MOD_HDF5_Input             ,ONLY: File_ID,DatasetExists,nDims,HSize
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
#if !(USE_HDG)
REAL,ALLOCATABLE                   :: U_local(:,:,:,:,:)
REAL,ALLOCATABLE                   :: U_local2(:,:,:,:,:)
INTEGER                            :: iPML
#endif
#if USE_HDG
LOGICAL                            :: DG_SolutionLambdaExists
LOGICAL                            :: DG_SolutionUExists
INTEGER(KIND=8)                    :: iter
#endif /*USE_HDG*/
INTEGER                            :: iElem
#if USE_MPI
REAL                               :: StartT,EndT
#endif /*USE_MPI*/
#ifdef PARTICLES
CHARACTER(LEN=255),ALLOCATABLE     :: StrVarNames(:)
CHARACTER(LEN=255),ALLOCATABLE     :: StrVarNames_HDF5(:)
INTEGER                            :: FirstElemInd,LastelemInd,j,k
INTEGER(KIND=IK),ALLOCATABLE       :: PartInt(:,:)
INTEGER,PARAMETER                  :: PartIntSize=2                  ! number of entries in each line of PartInt
INTEGER                            :: PartDataSize,PartDataSize_HDF5 ! number of entries in each line of PartData
INTEGER(KIND=IK)                   :: locnPart,offsetnPart,iLoop
INTEGER,PARAMETER                  :: ELEM_FirstPartInd=1
INTEGER,PARAMETER                  :: ELEM_LastPartInd=2
REAL,ALLOCATABLE                   :: PartData(:,:)
REAL                               :: xi(3)
LOGICAL                            :: InElementCheck,PartIntExists,PartDataExists,VibQuantDataExists,changedVars,DGSourceExists
LOGICAL                            :: ElecDistriDataExists, AD_DataExists
REAL                               :: det(6,2)
INTEGER                            :: NbrOfMissingParticles, CounterPoly
INTEGER, ALLOCATABLE               :: VibQuantData(:,:)
REAL, ALLOCATABLE                  :: ElecDistriData(:,:), AD_Data(:,:)
INTEGER                            :: MaxQuantNum, iPolyatMole, iSpec, iPart, iVar, MaxElecQuant, CounterElec, CounterAmbi
! 2D Symmetry RadialWeighting
LOGICAL                            :: CloneExists
#if USE_MPI
REAL, ALLOCATABLE                  :: SendBuff(:), RecBuff(:)
INTEGER                            :: TotalNbrOfMissingParticles(0:PartMPI%nProcs-1), Displace(0:PartMPI%nProcs-1),CurrentPartNum
INTEGER                            :: NbrOfFoundParts, CompleteNbrOfFound, RecCount(0:PartMPI%nProcs-1)
INTEGER, ALLOCATABLE               :: SendBuffPoly(:), RecBuffPoly(:)
REAL, ALLOCATABLE                  :: SendBuffAmbi(:), RecBuffAmbi(:), SendBuffElec(:), RecBuffElec(:)
INTEGER                            :: LostPartsPoly(0:PartMPI%nProcs-1), DisplacePoly(0:PartMPI%nProcs-1)
INTEGER                            :: LostPartsElec(0:PartMPI%nProcs-1), DisplaceElec(0:PartMPI%nProcs-1)
INTEGER                            :: LostPartsAmbi(0:PartMPI%nProcs-1), DisplaceAmbi(0:PartMPI%nProcs-1)
#endif /*USE_MPI*/
REAL,ALLOCATABLE                   :: PartSource_HDF5(:,:,:,:,:)
LOGICAL                            :: implemented
LOGICAL,ALLOCATABLE                :: readVarFromState(:)
INTEGER                            :: i
#endif
INTEGER(KIND=IK)                   :: PP_NTmp,OffsetElemTmp,PP_nVarTmp,PP_nElemsTmp,N_RestartTmp
#if USE_HDG
INTEGER                            :: SideID,iSide,MinGlobalSideID,MaxGlobalSideID
REAL,ALLOCATABLE                   :: ExtendedLambda(:,:,:)
INTEGER                            :: p,q,r,rr,pq(1:2)
INTEGER                            :: iLocSide,iLocSide_NB,iLocSide_master
INTEGER                            :: iMortar,MortarSideID,nMortars
#else
INTEGER(KIND=IK)                   :: PMLnVarTmp
#endif /*USE_HDG*/
!===================================================================================================================================
IF(DoRestart)THEN
#if USE_MPI
  StartT=MPI_WTIME()
#endif

  ! Temp. vars for integer KIND=8 possibility
  PP_NTmp       = INT(PP_N,IK)
  OffsetElemTmp = INT(OffsetElem,IK)
  PP_nVarTmp    = INT(PP_nVar,IK)
  PP_nElemsTmp  = INT(PP_nElems,IK)
  N_RestartTmp  = INT(N_Restart,IK)
#if !(USE_HDG)
  PMLnVarTmp    = INT(PMLnVar,IK)
#endif /*not USE_HDG*/
  ! ===========================================================================
  ! 1.) Read the field solution
  ! ===========================================================================
  IF(RestartNullifySolution)THEN ! Open the restart file and neglect the DG solution (only read particles if present)
    SWRITE(UNIT_stdOut,*)'Restarting from File: ',TRIM(RestartFile),' (but without reading the DG solution)'
    CALL OpenDataFile(RestartFile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.,communicatorOpt=MPI_COMM_WORLD)
  ELSE ! Use the solution in the restart file
    SWRITE(UNIT_stdOut,*)'Restarting from File: ',TRIM(RestartFile)
    CALL OpenDataFile(RestartFile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.,communicatorOpt=MPI_COMM_WORLD)
#ifdef PARTICLES
    !-- read PartSource if relaxation is performed (might be needed for RestartHDG)
    IF (DoDeposition .AND. RelaxDeposition) THEN
      CALL DatasetExists(File_ID,'DG_Source',DGSourceExists)
      IF(DGSourceExists)THEN
        IF(.NOT.InterpolateSolution)THEN! No interpolation needed, read solution directly from file
          ALLOCATE(PartSource_HDF5(1:4,0:PP_N,0:PP_N,0:PP_N,PP_nElems))
          CALL ReadArray('DG_Source' ,5,(/4_IK,PP_NTmp+1,PP_NTmp+1,PP_NTmp+1,PP_nElemsTmp/),OffsetElemTmp,5,RealArray=PartSource_HDF5)
          DO iElem =1, PP_nElems
            DO k=0, PP_N; DO j=0, PP_N; DO i=0, PP_N
#if ((USE_HDG) && (PP_nVar==1))
              PartSourceOld(1,1,i,j,k,iElem) = PartSource_HDF5(4,i,j,k,iElem)
              PartSourceOld(1,2,i,j,k,iElem) = PartSource_HDF5(4,i,j,k,iElem)
#else
              PartSourceOld(1:4,1,i,j,k,iElem) = PartSource_HDF5(1:4,i,j,k,iElem)
              PartSourceOld(1:4,2,i,j,k,iElem) = PartSource_HDF5(1:4,i,j,k,iElem)
#endif
            END DO; END DO; END DO
          END DO
          DEALLOCATE(PartSource_HDF5)
        ELSE! We need to interpolate the solution to the new computational grid
          CALL abort(&
              __STAMP__&
              ,' Restart with changed polynomial degree not implemented for DG_Source!')
        END IF
      END IF
    END IF
#endif /*PARTICLES*/
    ! Read in time from restart file
    !CALL ReadAttribute(File_ID,'Time',1,RealScalar=RestartTime)
    ! Read in state
    IF(.NOT. InterpolateSolution)THEN! No interpolation needed, read solution directly from file
#ifdef PP_POIS
#if (PP_nVar==8)
      CALL ReadArray('DG_SolutionE',5,(/PP_nVarTmp,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_nElemsTmp/),OffsetElemTmp,5,RealArray=U)
      CALL ReadArray('DG_SolutionPhi',5,(/4_IK,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_nElemsTmp/),OffsetElemTmp,5,RealArray=Phi)
#else
      CALL ReadArray('DG_SolutionE',5,(/PP_nVarTmp,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_nElemsTmp/),OffsetElemTmp,5,RealArray=U)
      CALL ReadArray('DG_SolutionPhi',5,(/PP_nVarTmp,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_nElemsTmp/),OffsetElemTmp,5,RealArray=Phi)
#endif
#elif USE_HDG
      CALL DatasetExists(File_ID,'DG_SolutionU',DG_SolutionUExists)
      IF(DG_SolutionUExists)THEN
        CALL ReadArray('DG_SolutionU',5,(/PP_nVarTmp,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_nElemsTmp/),OffsetElemTmp,5,RealArray=U)
      ELSE
        ! CALL abort(&
        !     __STAMP__&
        !     ,' DG_SolutionU does not exist in restart-file!')
        ! !DG_Solution contains a 4er-/3er-/7er-array, not PP_nVar!!!
        CALL ReadArray('DG_Solution' ,5,(/PP_nVarTmp,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_nElemsTmp/),OffsetElemTmp,5,RealArray=U)
      END IF



      ! Read HDG lambda solution (sorted in ascending global unique side ID ordering)
      CALL DatasetExists(File_ID,'DG_SolutionLambda',DG_SolutionLambdaExists)

      IF(DG_SolutionLambdaExists)THEN
        MinGlobalSideID = HUGE(1)
        MaxGlobalSideID = -1
        DO iSide = 1, nSides
          MaxGlobalSideID = MERGE(ABS(GlobalUniqueSideID(iSide)) , MaxGlobalSideID , ABS(GlobalUniqueSideID(iSide)).GT.MaxGlobalSideID)
          MinGlobalSideID = MERGE(ABS(GlobalUniqueSideID(iSide)) , MinGlobalSideID , ABS(GlobalUniqueSideID(iSide)).LT.MinGlobalSideID)
        END DO

        ASSOCIATE( &
              ExtendedOffsetSide => INT(MinGlobalSideID-1,IK)                 ,&
              ExtendednSides     => INT(MaxGlobalSideID-MinGlobalSideID+1,IK) ,&
              nGP_face           => INT(nGP_face,IK)                           )
          !ALLOCATE(ExtendedLambda(PP_nVar,nGP_face,MinGlobalSideID:MaxGlobalSideID))
          ALLOCATE(ExtendedLambda(PP_nVar,nGP_face,1:ExtendednSides))
          ExtendedLambda = HUGE(1.)
          lambda = HUGE(1.)
          CALL ReadArray('DG_SolutionLambda',3,(/PP_nVarTmp,nGP_face,ExtendednSides/),ExtendedOffsetSide,3,RealArray=ExtendedLambda)

          DO iSide = 1, nSides
            IF(iSide.LE.lastMPISide_MINE)THEN
              iLocSide        = SideToElem(S2E_LOC_SIDE_ID    , iSide)
              iLocSide_master = SideToElem(S2E_LOC_SIDE_ID    , iSide)
              iLocSide_NB     = SideToElem(S2E_NB_LOC_SIDE_ID , iSide)

              ! Check real small mortar side (when the same proc has both the big an one or more small side connected elements)
              IF(MortarType(1,iSide).EQ.0.AND.iLocSide_NB.NE.-1) iLocSide_master = iLocSide_NB

              ! is small virtual mortar side is encountered and no NB iLocSid_mastere is given
              IF(MortarType(1,iSide).EQ.0.AND.iLocSide_NB.EQ.-1)THEN
                ! check all my big mortar sides and find the one to which the small virtual is connected
                Check1: DO MortarSideID=firstMortarInnerSide,lastMortarInnerSide
                  nMortars=MERGE(4,2,MortarType(1,MortarSideID).EQ.1)
                  DO iMortar=1,nMortars
                    SideID= MortarInfo(MI_SIDEID,iMortar,MortarType(2,MortarSideID)) !small SideID
                    IF(iSide.EQ.SideID)THEN
                      iLocSide_master = SideToElem(S2E_LOC_SIDE_ID,MortarSideID)
                      IF(iLocSide_master.EQ.-1)THEN
                        CALL abort(&
                            __STAMP__&
                            ,'This big mortar side must be master')
                      END IF !iLocSide.NE.-1
                      EXIT Check1
                    END IF ! iSide.EQ.SideID
                  END DO !iMortar
                END DO Check1 !MortarSideID
              END IF ! MortarType(1,iSide).EQ.0

              DO q=0,PP_N
                DO p=0,PP_N
                  pq = CGNS_SideToVol2(PP_N,p,q,iLocSide_master)
                  r  = q    *(PP_N+1)+p    +1
                  rr = pq(2)*(PP_N+1)+pq(1)+1
                  lambda(:,r:r,iSide) = ExtendedLambda(:,rr:rr,GlobalUniqueSideID(iSide)-ExtendedOffsetSide)
                END DO
              END DO !p,q
            END IF ! iSide.LE.lastMPISide_MINE
          END DO
          DEALLOCATE(ExtendedLambda)
        END ASSOCIATE


#if USE_MPI
        ! Exchange lambda MINE -> YOUR direction (as only the master sides have read the solution until now)
        CALL StartReceiveMPIData(1,lambda,1,nSides, RecRequest_U,SendID=1) ! Receive YOUR
        CALL StartSendMPIData(   1,lambda,1,nSides,SendRequest_U,SendID=1) ! Send MINE
        CALL FinishExchangeMPIData(SendRequest_U,RecRequest_U,SendID=1)
#endif /*USE_MPI*/

        CALL RestartHDG(U) ! calls PostProcessGradient for calculate the derivative, e.g., the electric field E
      ELSE
        lambda=0.
      END IF

#else
      CALL ReadArray('DG_Solution',5,(/PP_nVarTmp,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_nElemsTmp/),OffsetElemTmp,5,RealArray=U)
      IF(DoPML)THEN
        ALLOCATE(U_local(PMLnVar,0:PP_N,0:PP_N,0:PP_N,PP_nElems))
        CALL ReadArray('PML_Solution',5,(/INT(PMLnVar,IK),PP_NTmp+1_IK,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_nElemsTmp/),&
            OffsetElemTmp,5,RealArray=U_local)
        DO iPML=1,nPMLElems
          U2(:,:,:,:,iPML) = U_local(:,:,:,:,PMLToElem(iPML))
        END DO ! iPML
        DEALLOCATE(U_local)
      END IF ! DoPML
#endif
      !CALL ReadState(RestartFile,PP_nVar,PP_N,PP_nElems,U)
    ELSE! We need to interpolate the solution to the new computational grid
      SWRITE(UNIT_stdOut,*)'Interpolating solution from restart grid with N=',N_restart,' to computational grid with N=',PP_N
#ifdef PP_POIS
#if (PP_nVar==8)
      ALLOCATE(U_local(PP_nVar,0:N_Restart,0:N_Restart,0:N_Restart,PP_nElems))
      CALL ReadArray('DG_SolutionE',5,(/PP_nVarTmp,N_RestartTmp+1_IK,N_RestartTmp+1_IK,N_RestartTmp+1_IK,PP_nElemsTmp/),&
          OffsetElemTmp,5,RealArray=U_local)
      DO iElem=1,PP_nElems
        CALL ChangeBasis3D(PP_nVar,N_Restart,PP_N,Vdm_GaussNRestart_GaussN,U_local(:,:,:,:,iElem),U(:,:,:,:,iElem))
      END DO
      DEALLOCATE(U_local)

      ALLOCATE(U_local(4,0:N_Restart,0:N_Restart,0:N_Restart,PP_nElems))
      CALL ReadArray('DG_SolutionPhi',5,(/4_IK,N_RestartTmp+1_IK,N_RestartTmp+1_IK,N_RestartTmp+1_IK,PP_nElemsTmp/),&
          OffsetElemTmp,5,RealArray=U_local)
      DO iElem=1,PP_nElems
        CALL ChangeBasis3D(4,N_Restart,PP_N,Vdm_GaussNRestart_GaussN,U_local(:,:,:,:,iElem),Phi(:,:,:,:,iElem))
      END DO
      DEALLOCATE(U_local)
#else
      ALLOCATE(U_local(PP_nVar,0:N_Restart,0:N_Restart,0:N_Restart,PP_nElems))
      CALL ReadArray('DG_SolutionE',5,(/PP_nVarTmp,N_RestartTmp+1_IK,N_RestartTmp+1_IK,N_RestartTmp+1_IK,PP_nElemsTmp/),&
          OffsetElemTmp,5,RealArray=U_local)
      DO iElem=1,PP_nElems
        CALL ChangeBasis3D(PP_nVar,N_Restart,PP_N,Vdm_GaussNRestart_GaussN,U_local(:,:,:,:,iElem),U(:,:,:,:,iElem))
      END DO
      CALL ReadArray('DG_SolutionPhi',5,(/PP_nVarTmp,N_RestartTmp+1_IK,N_RestartTmp+1_IK,N_RestartTmp+1_IK,PP_nElemsTmp/),&
          OffsetElemTmp,5,RealArray=U_local)
      DO iElem=1,PP_nElems
        CALL ChangeBasis3D(PP_nVar,N_Restart,PP_N,Vdm_GaussNRestart_GaussN,U_local(:,:,:,:,iElem),Phi(:,:,:,:,iElem))
      END DO
      DEALLOCATE(U_local)
#endif
#elif USE_HDG
      CALL abort(&
          __STAMP__&
          ,' Restart with changed polynomial degree not implemented for HDG!')
      !    ALLOCATE(U_local(PP_nVar,0:N_Restart,0:N_Restart,0:N_Restart,PP_nElems))
      !    CALL ReadArray('DG_SolutionLambda',5,(/PP_nVar,N_RestartTmp+1_IK,N_RestartTmp+1_IK,N_RestartTmp+1_IK,PP_nElemsTmp/),OffsetElem,5,RealArray=U_local)
      !    DO iElem=1,PP_nElems
      !      CALL ChangeBasis3D(PP_nVar,N_Restart,PP_N,Vdm_GaussNRestart_GaussN,U_local(:,:,:,:,iElem),U(:,:,:,:,iElem))
      !    END DO
      !    DEALLOCATE(U_local)
      !CALL RestartHDG(U)
#else
      ALLOCATE(U_local(PP_nVar,0:N_Restart,0:N_Restart,0:N_Restart,PP_nElems))
      CALL ReadArray('DG_Solution',5,(/PP_nVarTmp,N_RestartTmp+1_IK,N_RestartTmp+1_IK,N_RestartTmp+1_IK,PP_nElemsTmp/),&
          OffsetElemTmp,5,RealArray=U_local)
      DO iElem=1,PP_nElems
        CALL ChangeBasis3D(PP_nVar,N_Restart,PP_N,Vdm_GaussNRestart_GaussN,U_local(:,:,:,:,iElem),U(:,:,:,:,iElem))
      END DO
      DEALLOCATE(U_local)
      IF(DoPML)THEN
        ALLOCATE(U_local(PMLnVar,0:N_Restart,0:N_Restart,0:N_Restart,PP_nElems))
        ALLOCATE(U_local2(PMLnVar,0:PP_N,0:PP_N,0:PP_N,PP_nElems))
        CALL ReadArray('PML_Solution',5,(/INT(PMLnVar,IK),PP_NTmp+1_IK,PP_NTmp+1_IK,PP_NTmp+1_IK,PP_nElemsTmp/),&
            OffsetElemTmp,5,RealArray=U_local)
        DO iElem=1,PP_nElems
          CALL ChangeBasis3D(PMLnVar,N_Restart,PP_N,Vdm_GaussNRestart_GaussN,U_local(:,:,:,:,iElem),U_local2(:,:,:,:,iElem))
        END DO
        DO iPML=1,nPMLElems
          U2(:,:,:,:,iPML) = U_local2(:,:,:,:,PMLToElem(iPML))
        END DO ! iPML
        DEALLOCATE(U_local,U_local2)
      END IF ! DoPML
#endif
      SWRITE(UNIT_stdOut,*)' DONE!'
    END IF ! IF(.NOT. InterpolateSolution)
  END IF ! IF(.NOT. RestartNullifySolution)

#ifdef PARTICLES
  ! ------------------------------------------------
  ! NodeSourceExt (external/additional charge source terms)
  ! ------------------------------------------------
  IF(DoDielectricSurfaceCharge) CALL ReadNodeSourceExtFromHDF5()
#endif /*PARTICLES*/


#ifdef PARTICLES
  ! ===========================================================================
  ! 2.) Read the particle solution
  ! ===========================================================================
  implemented=.FALSE.
  IF(.NOT.DoMacroscopicRestart) THEN
    IF(useDSMC)THEN
      IF((CollisMode.GT.1).AND.(usevMPF).AND.(DSMC%ElectronicModel))THEN
        PartDataSize=11
        ALLOCATE(StrVarNames(PartDataSize))
        StrVarNames( 8)='Vibrational'
        StrVarNames( 9)='Rotational'
        StrVarNames(10)='Electronic'
        StrVarNames(11)='MPF'
        implemented = .TRUE.
      ELSE IF ( (CollisMode .GT. 1) .AND. (usevMPF) ) THEN
        PartDataSize=10
        ALLOCATE(StrVarNames(PartDataSize))
        StrVarNames( 8)='Vibrational'
        StrVarNames( 9)='Rotational'
        StrVarNames(10)='MPF'
        implemented = .TRUE.
      ELSE IF ( (CollisMode .GT. 1) .AND. (DSMC%ElectronicModel) ) THEN
        PartDataSize=10
        ALLOCATE(StrVarNames(PartDataSize))
        StrVarNames( 8)='Vibrational'
        StrVarNames( 9)='Rotational'
        StrVarNames(10)='Electronic'
      ELSE IF (CollisMode.GT.1) THEN
        implemented=.TRUE.
        PartDataSize=9 !int ener + 2
        ALLOCATE(StrVarNames(PartDataSize))
        StrVarNames( 8)='Vibrational'
        StrVarNames( 9)='Rotational'
      ELSE IF (usevMPF) THEN
        PartDataSize=8 !+ 1 vmpf
        ALLOCATE(StrVarNames(PartDataSize))
        StrVarNames( 8)='MPF'
        implemented=.TRUE.
      ELSE
        PartDataSize=7 !+ 0
        ALLOCATE(StrVarNames(PartDataSize))
      END IF
    ELSE IF (usevMPF) THEN
      PartDataSize=8 !vmpf +1
      ALLOCATE(StrVarNames(PartDataSize))
      StrVarNames( 8)='MPF'
    ELSE
      PartDataSize=7
      ALLOCATE(StrVarNames(PartDataSize))
    END IF ! UseDSMC
    StrVarNames(1)='ParticlePositionX'
    StrVarNames(2)='ParticlePositionY'
    StrVarNames(3)='ParticlePositionZ'
    StrVarNames(4)='VelocityX'
    StrVarNames(5)='VelocityY'
    StrVarNames(6)='VelocityZ'
    StrVarNames(7)='Species'
    ALLOCATE(readVarFromState(PartDataSize))
    readVarFromState=.TRUE.

    IF (useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
      MaxQuantNum = 0
      DO iSpec = 1, nSpecies
        IF(SpecDSMC(iSpec)%PolyatomicMol) THEN
          iPolyatMole = SpecDSMC(iSpec)%SpecToPolyArray
          IF (PolyatomMolDSMC(iPolyatMole)%VibDOF.GT.MaxQuantNum) MaxQuantNum = PolyatomMolDSMC(iPolyatMole)%VibDOF
        END IF ! SpecDSMC(iSpec)%PolyatomicMol
      END DO ! iSpec = 1, nSpecies
    END IF ! useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)

    IF (useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel) THEN
      MaxElecQuant = 0
      DO iSpec = 1, nSpecies
        IF (.NOT.((SpecDSMC(iSpec)%InterID.EQ.4).OR.SpecDSMC(iSpec)%FullyIonized)) THEN
          IF (SpecDSMC(iSpec)%MaxElecQuant.GT.MaxElecQuant) MaxElecQuant = SpecDSMC(iSpec)%MaxElecQuant
        END IF
      END DO
    END IF

    SWRITE(UNIT_stdOut,'(A)',ADVANCE='NO') ' Reading Particles from Restartfile...'
    !read local ElemInfo from HDF5
    FirstElemInd=offsetElem+1
    LastElemInd=offsetElem+PP_nElems
    ! read local ParticleInfo from HDF5
    CALL DatasetExists(File_ID,'PartInt',PartIntExists)
    IF(PartIntExists)THEN
      ALLOCATE(PartInt(FirstElemInd:LastElemInd,PartIntSize))

      ! Associate construct for integer KIND=8 possibility
      ASSOCIATE (&
            PP_nElems   => INT(PP_nElems,IK)   ,&
            PartIntSize => INT(PartIntSize,IK) ,&
            offsetElem  => INT(offsetElem,IK)   )
        CALL ReadArray('PartInt',2,(/PP_nElems,PartIntSize/),offsetElem,1,IntegerArray=PartInt)
      END ASSOCIATE
      ! read local Particle Data from HDF5
      locnPart=PartInt(LastElemInd,ELEM_LastPartInd)-PartInt(FirstElemInd,ELEM_FirstPartInd)
      offsetnPart=PartInt(FirstElemInd,ELEM_FirstPartInd)
      CALL DatasetExists(File_ID,'PartData',PartDataExists)
      IF(PartDataExists)THEN
        ! Read in parameters from the State file
        CALL GetDataSize(File_ID,'VarNamesParticles',nDims,HSize,attrib=.TRUE.)
        PartDataSize_HDF5 = INT(HSize(1),4)
        ALLOCATE(StrVarNames_HDF5(PartDataSize_HDF5))
        CALL ReadAttribute(File_ID,'VarNamesParticles',PartDataSize_HDF5,StrArray=StrVarNames_HDF5)
        IF (PartDataSize_HDF5.NE.PartDataSize) THEN
          changedVars=.TRUE.
        ELSE IF (.NOT.ALL(StrVarNames_HDF5.EQ.StrVarNames)) THEN
          changedVars=.TRUE.
        ELSE
          changedVars=.FALSE.
        END IF ! PartDataSize_HDF5.NE.PartDataSize
        IF (changedVars) THEN
          SWRITE(*,*) 'WARNING: VarNamesParticles have changed from restart-file!!!'
          IF (.NOT.implemented) CALL Abort(&
              __STAMP__&
              ,"not implemented yet!")
          readVarFromState=.FALSE.
          DO iVar=1,PartDataSize_HDF5
            IF (TRIM(StrVarNames(iVar)).EQ.TRIM(StrVarNames_HDF5(iVar))) THEN
              readVarFromState(iVar)=.TRUE.
            ELSE
              CALL Abort(&
                  __STAMP__&
                  ,"not associated VarNamesParticles in HDF5!")
            END IF
          END DO ! iVar=1,PartDataSize_HDF5
          DO iVar=1,PartDataSize
            IF (.NOT.readVarFromState(iVar)) THEN
              IF (TRIM(StrVarNames(iVar)).EQ.'Vibrational' .OR. TRIM(StrVarNames(iVar)).EQ.'Rotational') THEN
                SWRITE(*,*) 'WARNING: The following VarNamesParticles will be set to zero: '//TRIM(StrVarNames(iVar))
              ELSE IF(TRIM(StrVarNames(iVar)).EQ.'MPF') THEN
                SWRITE(*,*) 'WARNING: The particle weighting factor will be initialized with the given global weighting factor!'
              ELSE
                CALL Abort(&
                    __STAMP__&
                    ,"not associated VarNamesParticles to be reset!")
              END IF ! TRIM(StrVarNames(iVar)).EQ.'Vibrational' .OR. TRIM(StrVarNames(iVar)).EQ.'Rotational'
            END IF ! .NOT.readVarFromState(iVar)
          END DO ! iVar=1,PartDataSize
        END IF ! changedVars
        ALLOCATE(PartData(PartDataSize_HDF5,offsetnPart+1_IK:offsetnPart+locnPart))

        CALL ReadArray('PartData',2,(/INT(PartDataSize_HDF5,IK),locnPart/),offsetnPart,2,RealArray=PartData)!,&
        !xfer_mode_independent=.TRUE.)

        IF (useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0).AND.locnPart.GT.0) THEN
          CALL DatasetExists(File_ID,'VibQuantData',VibQuantDataExists)
          IF (.NOT.VibQuantDataExists) CALL abort(&
              __STAMP__&
              ,' Restart file does not contain "VibQuantData" in restart file for reading of polyatomic data')
          ALLOCATE(VibQuantData(MaxQuantNum,offsetnPart+1_IK:offsetnPart+locnPart))

          CALL ReadArray('VibQuantData',2,(/INT(MaxQuantNum,IK),locnPart/),offsetnPart,2,IntegerArray_i4=VibQuantData)
          !+1 is real number of necessary vib quants for the particle
        END IF ! useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)

        IF (useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel.AND.locnPart.GT.0) THEN
          CALL DatasetExists(File_ID,'ElecDistriData',ElecDistriDataExists)
          IF (.NOT.ElecDistriDataExists) CALL abort(&
              __STAMP__&
              ,' Restart file does not contain "ElecDistriDataExists" in restart file for reading of electronic data')
          ALLOCATE(ElecDistriData(MaxElecQuant,offsetnPart+1_IK:offsetnPart+locnPart))

          CALL ReadArray('ElecDistriData',2,(/INT(MaxElecQuant,IK),locnPart/),offsetnPart,2,RealArray=ElecDistriData)
          !+1 is real number of necessary vib quants for the particle
        END IF

        IF (useDSMC.AND.DSMC%DoAmbipolarDiff.AND.locnPart.GT.0) THEN
          CALL DatasetExists(File_ID,'ADVeloData',AD_DataExists)
          IF (.NOT.AD_DataExists) CALL abort(&
              __STAMP__&
              ,' Restart file does not contain "ADVeloData" in restart file for reading of ambipolar diffusion data')
          ALLOCATE(AD_Data(3,offsetnPart+1_IK:offsetnPart+locnPart))

          CALL ReadArray('ADVeloData',2,(/INT(3,IK),locnPart/),offsetnPart,2,RealArray=AD_Data)
          !+1 is real number of necessary vib quants for the particle
        END IF

        iPart=0
        DO iLoop = 1_IK,locnPart
          IF(SpecReset(INT(PartData(7,offsetnPart+iLoop),4))) CYCLE
          iPart = iPart + 1
          PartState(1,iPart)   = PartData(1,offsetnPart+iLoop)
          PartState(2,iPart)   = PartData(2,offsetnPart+iLoop)
          PartState(3,iPart)   = PartData(3,offsetnPart+iLoop)
          PartState(4,iPart)   = PartData(4,offsetnPart+iLoop)
          PartState(5,iPart)   = PartData(5,offsetnPart+iLoop)
          PartState(6,iPart)   = PartData(6,offsetnPart+iLoop)
          PartSpecies(iPart)= INT(PartData(7,offsetnPart+iLoop),4)
          IF (useDSMC) THEN
            IF ((CollisMode.GT.1).AND.(usevMPF) .AND. (DSMC%ElectronicModel)) THEN
              PartStateIntEn(1,iPart)=PartData(8,offsetnPart+iLoop)
              PartStateIntEn(2,iPart)=PartData(9,offsetnPart+iLoop)
              PartStateIntEn(3,iPart)=PartData(10,offsetnPart+iLoop)
              PartMPF(iPart)=PartData(11,offsetnPart+iLoop)
            ELSE IF ((CollisMode.GT.1).AND. (usevMPF)) THEN
              PartStateIntEn(1,iPart)=PartData(8,offsetnPart+iLoop)
              PartStateIntEn(2,iPart)=PartData(9,offsetnPart+iLoop)
              PartMPF(iPart)=PartData(10,offsetnPart+iLoop)
            ELSE IF ((CollisMode.GT.1).AND. (DSMC%ElectronicModel)) THEN
              PartStateIntEn(1,iPart)=PartData(8,offsetnPart+iLoop)
              PartStateIntEn(2,iPart)=PartData(9,offsetnPart+iLoop)
              PartStateIntEn(3,iPart)=PartData(10,offsetnPart+iLoop)
            ELSE IF (CollisMode.GT.1) THEN
              IF (readVarFromState(8).AND.readVarFromState(9)) THEN
                PartStateIntEn(1,iPart)=PartData(8,offsetnPart+iLoop)
                PartStateIntEn(2,iPart)=PartData(9,offsetnPart+iLoop)
              ELSE IF ((SpecDSMC(PartSpecies(iPart))%InterID.EQ.1).OR.&
                       (SpecDSMC(PartSpecies(iPart))%InterID.EQ.10).OR.&
                       (SpecDSMC(PartSpecies(iPart))%InterID.EQ.15)) THEN
                !- setting inner DOF to 0 for atoms
                PartStateIntEn(1,iPart)=0.
                PartStateIntEn(2,iPart)=0.
              ELSE
                CALL Abort(&
                    __STAMP__&
                    ,"resetting inner DOF for molecules is not implemented yet!"&
                ,SpecDSMC(PartSpecies(iPart))%InterID , PartData(7,offsetnPart+iLoop))
              END IF ! readVarFromState(8).AND.readVarFromState(9)
            ELSE IF (usevMPF) THEN
              PartMPF(iPart)=PartData(8,offsetnPart+iLoop)
            END IF ! (CollisMode.GT.1).AND.(usevMPF) .AND. (DSMC%ElectronicModel)
          ELSE IF (usevMPF) THEN
            PartMPF(iPart)=PartData(8,offsetnPart+iLoop)
          END IF ! UseDSMC

          IF (useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
            IF (SpecDSMC(PartSpecies(iPart))%PolyatomicMol) THEN
              iPolyatMole = SpecDSMC(PartSpecies(iPart))%SpecToPolyArray
              IF(ALLOCATED(VibQuantsPar(iPart)%Quants)) DEALLOCATE(VibQuantsPar(iPart)%Quants)
              ALLOCATE(VibQuantsPar(iPart)%Quants(PolyatomMolDSMC(iPolyatMole)%VibDOF))
              VibQuantsPar(iPart)%Quants(1:PolyatomMolDSMC(iPolyatMole)%VibDOF)= &
                  VibQuantData(1:PolyatomMolDSMC(iPolyatMole)%VibDOF,offsetnPart+iLoop)
            END IF ! SpecDSMC(PartSpecies(iPart))%PolyatomicMol
          END IF ! useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)

          IF (useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel) THEN
            IF (.NOT.((SpecDSMC(PartSpecies(iPart))%InterID.EQ.4).OR.SpecDSMC(PartSpecies(iPart))%FullyIonized)) THEN
              IF(ALLOCATED(ElectronicDistriPart(iPart)%DistriFunc)) DEALLOCATE(ElectronicDistriPart(iPart)%DistriFunc)
              ALLOCATE(ElectronicDistriPart(iPart)%DistriFunc(1:SpecDSMC(PartSpecies(iPart))%MaxElecQuant))
              ElectronicDistriPart(iPart)%DistriFunc(1:SpecDSMC(PartSpecies(iPart))%MaxElecQuant)= &
              ElecDistriData(1:SpecDSMC(PartSpecies(iPart))%MaxElecQuant,offsetnPart+iLoop)
            END IF
          END IF 

          IF (useDSMC.AND.DSMC%DoAmbipolarDiff) THEN
            IF (Species(PartSpecies(iPart))%ChargeIC.GT.0.0) THEN
              IF(ALLOCATED(AmbipolElecVelo(iPart)%ElecVelo)) DEALLOCATE(AmbipolElecVelo(iPart)%ElecVelo)
              ALLOCATE(AmbipolElecVelo(iPart)%ElecVelo(1:3))
              AmbipolElecVelo(iPart)%ElecVelo(1:3)= AD_Data(1:3,offsetnPart+iLoop)
            END IF
          END IF

          PDM%ParticleInside(iPart) = .TRUE.
        END DO ! iLoop = 1_IK,locnPart
        iPart = 0
        DO iElem=FirstElemInd,LastElemInd
          IF (PartInt(iElem,ELEM_LastPartInd).GT.PartInt(iElem,ELEM_FirstPartInd)) THEN
            DO iLoop = PartInt(iElem,ELEM_FirstPartInd)-offsetnPart+1_IK , PartInt(iElem,ELEM_LastPartInd)- offsetnPart
              IF(SpecReset(INT(PartData(7,offsetnPart+iLoop),4))) CYCLE
              iPart = iPart +1
              PEM%GlobalElemID(iPart)  = iElem
              PEM%LastGlobalElemID(iPart)  = iElem
            END DO ! iLoop
          END IF ! PartInt(iElem,ELEM_LastPartInd).GT.PartInt(iElem,ELEM_FirstPartInd)
        END DO ! iElem=FirstElemInd,LastElemInd
        DEALLOCATE(PartData)
        IF (useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
          SDEALLOCATE(VibQuantData)
        END IF
        IF (useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel) THEN
          SDEALLOCATE(ElecDistriData)
        END IF
        IF (useDSMC.AND.DSMC%DoAmbipolarDiff) THEN
          SDEALLOCATE(AD_Data)
        END IF
      ELSE ! not PartDataExists
        SWRITE(UNIT_stdOut,*)'PartData does not exists in restart file'
      END IF ! PartDataExists
      DEALLOCATE(PartInt)

      PDM%ParticleVecLength = PDM%ParticleVecLength + iPart
      CALL UpdateNextFreePosition()
      SWRITE(UNIT_stdOut,*)' DONE!'

      ! if ParticleVecLength GT maxParticleNumber: Stop
      IF (PDM%ParticleVecLength.GT.PDM%maxParticleNumber) THEN
        SWRITE (UNIT_stdOut,*) "PDM%ParticleVecLength =", PDM%ParticleVecLength
        SWRITE (UNIT_stdOut,*) "PDM%maxParticleNumber =", PDM%maxParticleNumber
        CALL abort(__STAMP__&
            ,' Number of Particles in Restart file is higher than MaxParticleNumber! Increase MaxParticleNumber!')
      END IF ! PDM%ParticleVecLength.GT.PDM%maxParticleNumber

      ! Since the elementside-local node number are NOT persistant and dependent on the location
      ! of the MPI borders, all particle-element mappings need to be checked after a restart
      ! Step 1: Identify particles that are not in the element in which they were before the restart
      NbrOfMissingParticles = 0
      NbrOfLostParticles    = 0
      CounterPoly           = 0
      CounterElec           = 0
      CounterAmbi           = 0

      SELECT CASE(TrackingMethod)
        CASE(TRIATRACKING)
          DO i = 1,PDM%ParticleVecLength
            ! Check if particle is inside the correct element
            CALL ParticleInsideQuad3D(PartState(1:3,i),PEM%GlobalElemID(i),InElementCheck,det)

            ! Particle not in correct element, try to find them within MyProc
            IF (.NOT.InElementCheck) THEN
              NbrOfMissingParticles = NbrOfMissingParticles + 1
              CALL LocateParticleInElement(i,doHALO=.FALSE.)

              ! Particle not found within MyProc
              IF (.NOT.PDM%ParticleInside(i)) THEN
                NbrOfLostParticles = NbrOfLostParticles + 1
#if !(USE_MPI)
                IF (CountNbrOfLostParts) CALL StoreLostParticleProperties(i, PEM%GlobalElemID(i), UsePartState_opt=.TRUE.)
#endif /*!(USE_MPI)*/
                IF (useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
                  IF (SpecDSMC(PartSpecies(i))%PolyatomicMol) THEN
                    iPolyatMole = SpecDSMC(PartSpecies(i))%SpecToPolyArray
                    CounterPoly = CounterPoly + PolyatomMolDSMC(iPolyatMole)%VibDOF
                  END IF
                END IF
                IF (useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel) THEN
                  IF (.NOT.((SpecDSMC(PartSpecies(i))%InterID.EQ.4).OR.SpecDSMC(PartSpecies(i))%FullyIonized)) THEN
                    CounterElec = CounterElec + SpecDSMC(PartSpecies(i))%MaxElecQuant
                  END IF
                END IF
                IF (useDSMC.AND.DSMC%DoAmbipolarDiff) THEN
                  IF (Species(PartSpecies(i))%ChargeIC.GT.0.0) THEN
                    CounterAmbi = CounterAmbi + 3
                  END IF
                END IF
              ELSE
                PEM%LastGlobalElemID(i) = PEM%GlobalElemID(i)
              END IF
            END IF
          END DO ! i = 1,PDM%ParticleVecLength

        CASE(TRACING)
          DO i = 1,PDM%ParticleVecLength
            ! Check if particle is inside the correct element
            CALL GetPositionInRefElem(PartState(1:3,i),Xi,PEM%GlobalElemID(i))
            IF (ALL(ABS(Xi).LE.1.0)) THEN ! particle inside
              InElementCheck = .TRUE.
              IF(ALLOCATED(PartPosRef)) PartPosRef(1:3,i)=Xi
            ELSE
              InElementCheck = .FALSE.
            END IF

            ! Particle not in correct element, try to find them within MyProc
            IF (.NOT.InElementCheck) THEN
              NbrOfMissingParticles = NbrOfMissingParticles + 1
              CALL LocateParticleInElement(i,doHALO=.FALSE.)

              ! Particle not found within MyProc
              IF (.NOT.PDM%ParticleInside(i)) THEN
                NbrOfLostParticles = NbrOfLostParticles + 1
#if !(USE_MPI)
                IF (CountNbrOfLostParts) CALL StoreLostParticleProperties(i, PEM%GlobalElemID(i), UsePartState_opt=.TRUE.)
#endif /*!(USE_MPI)*/
                IF (useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
                  IF (SpecDSMC(PartSpecies(i))%PolyatomicMol) THEN
                    iPolyatMole = SpecDSMC(PartSpecies(i))%SpecToPolyArray
                    CounterPoly = CounterPoly + PolyatomMolDSMC(iPolyatMole)%VibDOF
                  END IF
                END IF
                IF (useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel) THEN
                  IF (.NOT.((SpecDSMC(PartSpecies(i))%InterID.EQ.4).OR.SpecDSMC(PartSpecies(i))%FullyIonized)) THEN
                    CounterElec = CounterElec + SpecDSMC(PartSpecies(i))%MaxElecQuant
                  END IF
                END IF
                IF (useDSMC.AND.DSMC%DoAmbipolarDiff) THEN
                  IF (Species(PartSpecies(i))%ChargeIC.GT.0.0) THEN
                    CounterAmbi = CounterAmbi + 3
                  END IF
                END IF
              ELSE
                PEM%LastGlobalElemID(i) = PEM%GlobalElemID(i)
              END IF ! .NOT.PDM%ParticleInside(i)
            END IF ! .NOT.InElementCheck
          END DO ! i = 1,PDM%ParticleVecLength

        CASE(REFMAPPING)
          DO i = 1,PDM%ParticleVecLength
            ! Check if particle is inside the correct element
            CALL GetPositionInRefElem(PartState(1:3,i),Xi,PEM%GlobalElemID(i))
            IF (ALL(ABS(Xi).LE.ElemEpsOneCell(PEM%GlobalElemID(i)))) THEN ! particle inside
              InElementCheck    = .TRUE.
              PartPosRef(1:3,i) = Xi
            ELSE
              InElementCheck    = .FALSE.
            END IF

            ! Particle not in correct element, try to find them within MyProc
            IF (.NOT.InElementCheck) THEN
              NbrOfMissingParticles = NbrOfMissingParticles + 1
              CALL LocateParticleInElement(i,doHALO=.FALSE.)

              ! Particle not found within MyProc
              IF (.NOT.PDM%ParticleInside(i)) THEN
                NbrOfLostParticles = NbrOfLostParticles + 1
#if !(USE_MPI)
                IF (CountNbrOfLostParts) CALL StoreLostParticleProperties(i, PEM%GlobalElemID(i), UsePartState_opt=.TRUE.)
#endif /*!(USE_MPI)*/
                IF (useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
                  IF (SpecDSMC(PartSpecies(i))%PolyatomicMol) THEN
                    iPolyatMole = SpecDSMC(PartSpecies(i))%SpecToPolyArray
                    CounterPoly = CounterPoly + PolyatomMolDSMC(iPolyatMole)%VibDOF
                  END IF
                END IF
                IF (useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel) THEN
                  IF (.NOT.((SpecDSMC(PartSpecies(i))%InterID.EQ.4).OR.SpecDSMC(PartSpecies(i))%FullyIonized)) THEN
                    CounterElec = CounterElec + SpecDSMC(PartSpecies(i))%MaxElecQuant
                  END IF
                END IF
                IF (useDSMC.AND.DSMC%DoAmbipolarDiff) THEN
                  IF (Species(PartSpecies(i))%ChargeIC.GT.0.0) THEN
                    CounterAmbi = CounterAmbi + 3
                  END IF
                END IF
                PartPosRef(1:3,i) = -888.
              ELSE
                PEM%LastGlobalElemID(i) = PEM%GlobalElemID(i)
              END IF
            END IF
          END DO ! i = 1,PDM%ParticleVecLength
      END SELECT


#if USE_MPI
      ! Step 2: All particles that are not found within MyProc need to be communicated to the others and located there
      ! Combine number of lost particles of all processes and allocate variables
      CALL MPI_ALLGATHER(NbrOfLostParticles, 1, MPI_INTEGER, TotalNbrOfMissingParticles, 1, MPI_INTEGER, PartMPI%COMM, IERROR)
      IF(useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) CALL MPI_ALLGATHER(CounterPoly, 1, MPI_INTEGER, LostPartsPoly, 1, MPI_INTEGER, &
                                                                       PartMPI%COMM, IERROR)
      IF(useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel) &
        CALL MPI_ALLGATHER(CounterElec, 1, MPI_INTEGER, LostPartsElec, 1, MPI_INTEGER, PartMPI%COMM, IERROR)
      IF(useDSMC.AND.DSMC%DoAmbipolarDiff) &
        CALL MPI_ALLGATHER(CounterAmbi, 1, MPI_INTEGER, LostPartsAmbi, 1, MPI_INTEGER, PartMPI%COMM, IERROR)
      ! Check total number of missing particles and start re-locating them on other procs
      IF (SUM(TotalNbrOfMissingParticles).GT.0) THEN
        ALLOCATE(SendBuff(1:NbrOfLostParticles*PartDataSize))
        ALLOCATE(RecBuff(1:SUM(TotalNbrOfMissingParticles)*PartDataSize))
        IF(useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
          ALLOCATE(SendBuffPoly(1:CounterPoly))
          ALLOCATE(RecBuffPoly(1:SUM(LostPartsPoly)))
        END IF
        IF(useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel) THEN
          ALLOCATE(SendBuffElec(1:CounterElec))
          ALLOCATE(RecBuffElec(1:SUM(LostPartsElec)))
        END IF
        IF(useDSMC.AND.DSMC%DoAmbipolarDiff) THEN
          ALLOCATE(SendBuffAmbi(1:CounterAmbi))
          ALLOCATE(RecBuffAmbi(1:SUM(LostPartsAmbi)))
        END IF
        ! Fill SendBuffer
        NbrOfMissingParticles = 0
        CounterPoly = 0
        CounterAmbi = 0
        CounterElec = 0
        DO i = 1, PDM%ParticleVecLength
          IF (.NOT.PDM%ParticleInside(i)) THEN
            SendBuff(NbrOfMissingParticles+1:NbrOfMissingParticles+6) = PartState(1:6,i)
            SendBuff(NbrOfMissingParticles+7)           = REAL(PartSpecies(i))
            IF (useDSMC) THEN
              IF ((CollisMode.GT.1).AND.(usevMPF) .AND. (DSMC%ElectronicModel)) THEN
                SendBuff(NbrOfMissingParticles+8)  = PartStateIntEn(1,i)
                SendBuff(NbrOfMissingParticles+9)  = PartStateIntEn(2,i)
                SendBuff(NbrOfMissingParticles+10) = PartMPF(i)
                SendBuff(NbrOfMissingParticles+11) = PartStateIntEn(3,i)
              ELSE IF ((CollisMode.GT.1).AND. (usevMPF)) THEN
                SendBuff(NbrOfMissingParticles+8)  = PartStateIntEn(1,i)
                SendBuff(NbrOfMissingParticles+9)  = PartStateIntEn(2,i)
                SendBuff(NbrOfMissingParticles+10) = PartMPF(i)
              ELSE IF ((CollisMode.GT.1).AND. (DSMC%ElectronicModel)) THEN
                SendBuff(NbrOfMissingParticles+8)  = PartStateIntEn(1,i)
                SendBuff(NbrOfMissingParticles+9)  = PartStateIntEn(2,i)
                SendBuff(NbrOfMissingParticles+10) = PartStateIntEn(3,i)
              ELSE IF (CollisMode.GT.1) THEN
                SendBuff(NbrOfMissingParticles+8)  = PartStateIntEn(1,i)
                SendBuff(NbrOfMissingParticles+9)  = PartStateIntEn(2,i)
              ELSE IF (usevMPF) THEN
                SendBuff(NbrOfMissingParticles+8) = PartMPF(i)
              END IF
            ELSE IF (usevMPF) THEN
              SendBuff(NbrOfMissingParticles+8) = PartMPF(i)
            END IF
            NbrOfMissingParticles = NbrOfMissingParticles + PartDataSize

            !--- receive the polyatomic vibquants per particle at the end of the message
            IF(useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
              IF(SpecDSMC(PartSpecies(i))%PolyatomicMol) THEN
                iPolyatMole = SpecDSMC(PartSpecies(i))%SpecToPolyArray
                SendBuffPoly(CounterPoly+1:CounterPoly+PolyatomMolDSMC(iPolyatMole)%VibDOF) &
                    = VibQuantsPar(i)%Quants(1:PolyatomMolDSMC(iPolyatMole)%VibDOF)
                CounterPoly = CounterPoly + PolyatomMolDSMC(iPolyatMole)%VibDOF
              END IF ! SpecDSMC(PartSpecies(i))%PolyatomicMol
            END IF ! useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)
            !--- receive the polyatomic vibquants per particle at the end of the message
            IF(useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel)  THEN
              IF (.NOT.((SpecDSMC(PartSpecies(i))%InterID.EQ.4).OR.SpecDSMC(PartSpecies(i))%FullyIonized)) THEN
                SendBuffElec(CounterElec+1:CounterElec+SpecDSMC(PartSpecies(i))%MaxElecQuant) &
                    = ElectronicDistriPart(i)%DistriFunc(1:SpecDSMC(PartSpecies(i))%MaxElecQuant)
                CounterElec = CounterElec + SpecDSMC(PartSpecies(i))%MaxElecQuant
              END IF !
            END IF ! 
            IF(useDSMC.AND.DSMC%DoAmbipolarDiff)  THEN
              IF (Species(PartSpecies(i))%ChargeIC.GT.0.0)  THEN
                SendBuffAmbi(CounterAmbi+1:CounterAmbi+3) = AmbipolElecVelo(i)%ElecVelo(1:3)
                CounterAmbi = CounterAmbi + 3
              END IF !
            END IF ! 

          END IF ! .NOT.PDM%ParticleInside(i)
        END DO ! i = 1, PDM%ParticleVecLength
        ! Distribute lost particles to all procs
        NbrOfMissingParticles = 0
        CounterPoly = 0
        CounterElec = 0
        CounterAmbi = 0
        DO i = 0, PartMPI%nProcs-1
          RecCount(i) = TotalNbrOfMissingParticles(i) * PartDataSize
          Displace(i) = NbrOfMissingParticles
          NbrOfMissingParticles = NbrOfMissingParticles + TotalNbrOfMissingParticles(i)*PartDataSize
          IF(useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
            DisplacePoly(i) = CounterPoly
            CounterPoly = CounterPoly + LostPartsPoly(i)
          END IF
          IF(useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel)  THEN
            DisplaceElec(i) = CounterElec
            CounterElec = CounterElec + LostPartsElec(i)
          END IF
          IF(useDSMC.AND.DSMC%DoAmbipolarDiff)  THEN
            DisplaceAmbi(i) = CounterAmbi
            CounterAmbi = CounterAmbi + LostPartsAmbi(i)
          END IF
        END DO ! i = 0, PartMPI%nProcs-1
        CALL MPI_ALLGATHERV(SendBuff, PartDataSize*TotalNbrOfMissingParticles(PartMPI%MyRank), MPI_DOUBLE_PRECISION, &
            RecBuff, RecCount, Displace, MPI_DOUBLE_PRECISION, PartMPI%COMM, IERROR)
        IF(useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) CALL MPI_ALLGATHERV(SendBuffPoly, LostPartsPoly(PartMPI%MyRank), MPI_INTEGER, &
            RecBuffPoly, LostPartsPoly, DisplacePoly, MPI_INTEGER, PartMPI%COMM, IERROR)
        IF(useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel) &
         CALL MPI_ALLGATHERV(SendBuffElec, LostPartsElec(PartMPI%MyRank), MPI_INTEGER, & 
              RecBuffElec, LostPartsElec, DisplaceElec, MPI_DOUBLE_PRECISION, PartMPI%COMM, IERROR)
        IF(useDSMC.AND.DSMC%DoAmbipolarDiff) &
         CALL MPI_ALLGATHERV(SendBuffAmbi, LostPartsAmbi(PartMPI%MyRank), MPI_INTEGER, & 
              RecBuffAmbi, LostPartsAmbi, DisplaceAmbi, MPI_DOUBLE_PRECISION, PartMPI%COMM, IERROR)
        ! Add them to particle list and check if they are in MyProcs domain
        NbrOfFoundParts = 0
        CurrentPartNum  = PDM%ParticleVecLength+1
        NbrOfMissingParticles = 0
        CounterPoly = 0
        CounterElec = 0
        CounterAmbi = 0
        DO i = 1, SUM(TotalNbrOfMissingParticles)
          PartState(1:6,CurrentPartNum) = RecBuff(NbrOfMissingParticles+1:NbrOfMissingParticles+6)
          PDM%ParticleInside(CurrentPartNum) = .true.
          CALL LocateParticleInElement(CurrentPartNum,doHALO=.FALSE.)
          IF (PDM%ParticleInside(CurrentPartNum)) THEN
            PEM%LastGlobalElemID(CurrentPartNum) = PEM%GlobalElemID(CurrentPartNum)
!            NbrOfMissingParticles = NbrOfMissingParticles + 1

            ! Set particle properties (if the particle is lost, it's properties are written to a .h5 file)
            PartSpecies(CurrentPartNum) = INT(RecBuff(NbrOfMissingParticles+7))
            IF (useDSMC) THEN
              IF ((CollisMode.GT.1).AND.(usevMPF) .AND. (DSMC%ElectronicModel)) THEN
                PartStateIntEn(1,CurrentPartNum) = RecBuff(NbrOfMissingParticles+8)
                PartStateIntEn(2,CurrentPartNum) = RecBuff(NbrOfMissingParticles+9)
                PartStateIntEn(3,CurrentPartNum) = RecBuff(NbrOfMissingParticles+11)
                PartMPF(CurrentPartNum)          = RecBuff(NbrOfMissingParticles+10)
              ELSE IF ((CollisMode.GT.1).AND. (usevMPF)) THEN
                PartStateIntEn(1,CurrentPartNum) = RecBuff(NbrOfMissingParticles+8)
                PartStateIntEn(2,CurrentPartNum) = RecBuff(NbrOfMissingParticles+9)
                PartMPF(CurrentPartNum)          = RecBuff(NbrOfMissingParticles+10)
              ELSE IF ((CollisMode.GT.1).AND. (DSMC%ElectronicModel)) THEN
                PartStateIntEn(1,CurrentPartNum) = RecBuff(NbrOfMissingParticles+8)
                PartStateIntEn(2,CurrentPartNum) = RecBuff(NbrOfMissingParticles+9)
                PartStateIntEn(3,CurrentPartNum) = RecBuff(NbrOfMissingParticles+10)
              ELSE IF (CollisMode.GT.1) THEN
                PartStateIntEn(1,CurrentPartNum) = RecBuff(NbrOfMissingParticles+8)
                PartStateIntEn(2,CurrentPartNum) = RecBuff(NbrOfMissingParticles+9)
              ELSE IF (usevMPF) THEN
                PartMPF(CurrentPartNum)          = RecBuff(NbrOfMissingParticles+8)
              END IF
            ELSE IF (usevMPF) THEN
              PartMPF(CurrentPartNum)          = RecBuff(NbrOfMissingParticles+8)
            END IF
            NbrOfFoundParts = NbrOfFoundParts + 1
            ! Check if particle was found inside of an element
            IF(useDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
              IF(SpecDSMC(PartSpecies(CurrentPartNum))%PolyatomicMol) THEN
                iPolyatMole = SpecDSMC(PartSpecies(CurrentPartNum))%SpecToPolyArray
                IF(ALLOCATED(VibQuantsPar(CurrentPartNum)%Quants)) DEALLOCATE(VibQuantsPar(CurrentPartNum)%Quants)
                ALLOCATE(VibQuantsPar(CurrentPartNum)%Quants(PolyatomMolDSMC(iPolyatMole)%VibDOF))
                VibQuantsPar(CurrentPartNum)%Quants(1:PolyatomMolDSMC(iPolyatMole)%VibDOF) &
                    = RecBuffPoly(CounterPoly+1:CounterPoly+PolyatomMolDSMC(iPolyatMole)%VibDOF)
                CounterPoly = CounterPoly + PolyatomMolDSMC(iPolyatMole)%VibDOF
              END IF
            END IF
            IF(useDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel)  THEN
              IF (.NOT.((SpecDSMC(PartSpecies(CurrentPartNum))%InterID.EQ.4) & 
                  .OR.SpecDSMC(PartSpecies(CurrentPartNum))%FullyIonized)) THEN
                IF(ALLOCATED(ElectronicDistriPart(CurrentPartNum)%DistriFunc)) &  
                  DEALLOCATE(ElectronicDistriPart(CurrentPartNum)%DistriFunc)
                ALLOCATE(ElectronicDistriPart(CurrentPartNum)%DistriFunc(1:SpecDSMC(PartSpecies(CurrentPartNum))%MaxElecQuant))
                ElectronicDistriPart(CurrentPartNum)%DistriFunc(1:SpecDSMC(PartSpecies(CurrentPartNum))%MaxElecQuant)= &
                  RecBuffElec(CounterElec+1:CounterElec+SpecDSMC(PartSpecies(CurrentPartNum))%MaxElecQuant)
                CounterElec = CounterElec +SpecDSMC(PartSpecies(CurrentPartNum))%MaxElecQuant
              END IF
            END IF
            IF(useDSMC.AND.DSMC%DoAmbipolarDiff)  THEN
              IF (Species(PartSpecies(CurrentPartNum))%ChargeIC.GT.0.0) THEN
                IF(ALLOCATED(AmbipolElecVelo(CurrentPartNum)%ElecVelo)) DEALLOCATE(AmbipolElecVelo(CurrentPartNum)%ElecVelo)
                ALLOCATE(AmbipolElecVelo(CurrentPartNum)%ElecVelo(1:3))
                AmbipolElecVelo(CurrentPartNum)%ElecVelo(1:3)= RecBuffAmbi(CounterAmbi+1:CounterAmbi+3)
                CounterAmbi = CounterAmbi + 3
              END IF
            END IF
            CurrentPartNum = CurrentPartNum + 1
          ELSE ! Particle could not be found and is therefore lost
            ! Save particle properties for writing to a .h5 file
!             This call makes no sense here! EVERY proc gets the particle, so only one can find it in the first place
!            IF(CountNbrOfLostParts) CALL StoreLostParticleProperties(CurrentPartNum, PEM%GlobalElemID(CurrentPartNum), UsePartState_opt=.TRUE.)
          END IF
          NbrOfMissingParticles = NbrOfMissingParticles + PartDataSize
        END DO ! i = 1, SUM(TotalNbrOfMissingParticles)
        PDM%ParticleVecLength = PDM%ParticleVecLength + NbrOfFoundParts
        ! Combine number of found particles to make sure none are lost completely
        CALL MPI_ALLREDUCE(NbrOfFoundParts, CompleteNbrOfFound, 1, MPI_INTEGER, MPI_SUM, PartMPI%COMM, IERROR)
        NbrOfLostParticlesTotal = SUM(TotalNbrOfMissingParticles)-CompleteNbrOfFound
        SWRITE(UNIT_stdOut,*) SUM(TotalNbrOfMissingParticles),'were not in the correct proc after restart.'
        SWRITE(UNIT_stdOut,*) CompleteNbrOfFound,'of these were found in other procs.'
        SWRITE(UNIT_stdOut,*) NbrOfLostParticlesTotal,'were not found and have been removed.'
!        SWRITE(UNIT_stdOut,*)'The lost particles have been written to PartStateLost*.h5.'
!        SWRITE(UNIT_stdOut,*)'Note that also missing particles will be written to that file and '//&
!                             'it will therefore contain a mix of missing and lost particles.'
      END IF ! SUM(TotalNbrOfMissingParticles).GT.0
#else /*not USE_MPI*/
      NbrOfLostParticlesTotal=NbrOfLostParticles
      IF (NbrOfMissingParticles.NE.0) WRITE(*,*) NbrOfMissingParticles,'Particles are in different element after restart!'
      IF (NbrOfLostParticles   .NE.0) THEN
        WRITE(UNIT_stdOut,*) NbrOfLostParticlesTotal,' could not be found and have been removed!.'
        WRITE(UNIT_stdOut,*)'The lost particles have been written to PartStateLost*.h5.'
      END IF ! NbrOfLostParticles.NE.0
#endif /*USE_MPI*/

      CALL UpdateNextFreePosition()

      IF (RadialWeighting%PerformCloning) THEN
        CALL DatasetExists(File_ID,'CloneData',CloneExists)
        IF(CloneExists) THEN
          CALL RestartClones()
        ELSE
          SWRITE(*,*) 'No clone data found! Restart without cloning.'
          IF(RadialWeighting%CloneMode.EQ.1) THEN
            RadialWeighting%CloneDelayDiff = 1
          ELSEIF (RadialWeighting%CloneMode.EQ.2) THEN
            RadialWeighting%CloneDelayDiff = 0
          END IF ! RadialWeighting%CloneMode.EQ.1
        END IF ! CloneExists
      END IF ! RadialWeighting%PerformCloning
    ELSE ! not PartIntExists
      SWRITE(UNIT_stdOut,*)'PartInt does not exists in restart file'
    END IF ! PartIntExists
  ELSE ! DoMacroscopicRestart
    CALL CloseDataFile()
    CALL MacroscopicRestart()
    CALL UpdateNextFreePosition()
  END IF ! .NOT.DoMacroscopicRestart

#endif /*PARTICLES*/

CALL CloseDataFile()

#if USE_HDG
  iter=0
  ! INSTEAD OF ALL THIS STUFF DO
  ! 1) MPI-Communication for shape-function particles
  ! 2) Deposition
  ! 3) ONE HDG solve
  CALL  RecomputeLambda(RestartTime)
#endif /*USE_HDG*/


  ! Delete all files that will be rewritten
  CALL FlushHDF5(RestartTime)
#if USE_MPI
  EndT=MPI_WTIME()
  SWRITE(UNIT_stdOut,'(A,F0.3,A)',ADVANCE='YES')' Restart took  [',EndT-StartT,'s] for readin.'
  SWRITE(UNIT_stdOut,'(a)',ADVANCE='YES')' Restart DONE!'
#else
  SWRITE(UNIT_stdOut,'(a)',ADVANCE='YES')' Restart DONE!'
#endif
ELSE ! no restart
  ! Delete all files since we are doing a fresh start
  CALL FlushHDF5()
END IF !IF(DoRestart)
END SUBROUTINE Restart

#ifdef PARTICLES
SUBROUTINE RestartClones()
!===================================================================================================================================
! Axisymmetric 2D simulation with particle weighting: Read-in of clone particles saved during output of particle data
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_HDF5_input
USE MOD_io_hdf5
USE MOD_Mesh_Vars,                ONLY : offsetElem, nElems
USE MOD_DSMC_Vars,                ONLY : UseDSMC, CollisMode, DSMC, PolyatomMolDSMC, SpecDSMC
USE MOD_DSMC_Vars,                ONLY : RadialWeighting, ClonedParticles
USE MOD_Particle_Vars,            ONLY : nSpecies, usevMPF, Species
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
  INTEGER                           :: nDimsClone, CloneDataSize, ClonePartNum, iPart, iDelay, maxDelay, iElem, tempDelay
  INTEGER(HSIZE_T), POINTER         :: SizeClone(:)
  REAL,ALLOCATABLE                  :: CloneData(:,:)
  INTEGER                           :: iPolyatmole, MaxQuantNum, iSpec, compareDelay, MaxElecQuant
  INTEGER,ALLOCATABLE               :: pcount(:), VibQuantData(:,:)
  REAL, ALLOCATABLE                 :: ElecDistriData(:,:), AD_Data(:,:)
!===================================================================================================================================

  CALL GetDataSize(File_ID,'CloneData',nDimsClone,SizeClone)

  CloneDataSize = INT(SizeClone(1),4)
  ClonePartNum = INT(SizeClone(2),4)
  DEALLOCATE(SizeClone)

  IF(ClonePartNum.GT.0) THEN
    ALLOCATE(CloneData(1:CloneDataSize,1:ClonePartNum))
    ASSOCIATE(ClonePartNum  => INT(ClonePartNum,IK)  ,&
              CloneDataSize => INT(CloneDataSize,IK) )
      CALL ReadArray('CloneData',2,(/CloneDataSize,ClonePartNum/),0_IK,2,RealArray=CloneData)
    END ASSOCIATE
    SWRITE(*,*) 'Read-in of cloned particles complete. Total clone number: ', ClonePartNum
    ! Determing the old clone delay
    maxDelay = INT(MAXVAL(CloneData(9,:)))
    IF(RadialWeighting%CloneMode.EQ.1) THEN
      ! Array is allocated from 0 to maxDelay
      compareDelay = maxDelay + 1
    ELSE
      compareDelay = maxDelay
    END IF
    IF(compareDelay.GT.RadialWeighting%CloneInputDelay) THEN
      SWRITE(*,*) 'Old clone delay is greater than the new delay. Old delay:', compareDelay
      RadialWeighting%CloneDelayDiff = RadialWeighting%CloneInputDelay + 1
    ELSEIF(compareDelay.EQ.RadialWeighting%CloneInputDelay) THEN
      SWRITE(*,*) 'The clone delay has not been changed.'
      RadialWeighting%CloneDelayDiff = RadialWeighting%CloneInputDelay + 1
    ELSE
      SWRITE(*,*) 'New clone delay is greater than the old delay. Old delay:', compareDelay
      RadialWeighting%CloneDelayDiff = compareDelay + 1
    END IF
    IF(RadialWeighting%CloneMode.EQ.1) THEN
      tempDelay = RadialWeighting%CloneInputDelay - 1
    ELSE
      tempDelay = RadialWeighting%CloneInputDelay
    END IF
    ALLOCATE(pcount(0:tempDelay))
    pcount(0:tempDelay) = 0
    ! Polyatomic clones: determining the size of the VibQuant array
    IF (UseDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
      MaxQuantNum = 0
      DO iSpec = 1, nSpecies
        IF(SpecDSMC(iSpec)%PolyatomicMol) THEN
          iPolyatMole = SpecDSMC(iSpec)%SpecToPolyArray
          IF (PolyatomMolDSMC(iPolyatMole)%VibDOF.GT.MaxQuantNum) MaxQuantNum = PolyatomMolDSMC(iPolyatMole)%VibDOF
        END IF
      END DO
      ALLOCATE(VibQuantData(1:MaxQuantNum,1:ClonePartNum))
      ASSOCIATE(ClonePartNum => INT(ClonePartNum,IK),MaxQuantNum => INT(MaxQuantNum,IK))
        CALL ReadArray('CloneVibQuantData',2,(/MaxQuantNum,ClonePartNum/),0_IK,2,IntegerArray_i4=VibQuantData)
      END ASSOCIATE
    END IF
    IF (UseDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel) THEN
      MaxElecQuant = 0
      DO iSpec = 1, nSpecies
        IF (.NOT.((SpecDSMC(iSpec)%InterID.EQ.4).OR.SpecDSMC(iSpec)%FullyIonized)) THEN
          IF (SpecDSMC(iSpec)%MaxElecQuant.GT.MaxElecQuant) MaxElecQuant = SpecDSMC(iSpec)%MaxElecQuant
        END IF
      END DO
      ALLOCATE(ElecDistriData(1:MaxElecQuant,1:ClonePartNum))
      ASSOCIATE(ClonePartNum => INT(ClonePartNum,IK),MaxElecQuant => INT(MaxElecQuant,IK))
        CALL ReadArray('CloneElecDistriData',2,(/MaxElecQuant,ClonePartNum/),0_IK,2,RealArray=ElecDistriData)
      END ASSOCIATE
    END IF
    IF (UseDSMC.AND.DSMC%DoAmbipolarDiff) THEN
      ALLOCATE(AD_Data(1:3,1:ClonePartNum))
      ASSOCIATE(ClonePartNum => INT(ClonePartNum,IK))
        CALL ReadArray('CloneADVeloData',2,(/INT(3,IK),ClonePartNum/),0_IK,2,RealArray=AD_Data)
      END ASSOCIATE
    END IF
    ! Copying particles into ClonedParticles array
    DO iPart = 1, ClonePartNum
      iDelay = INT(CloneData(9,iPart))
      iElem = INT(CloneData(8,iPart)) - offsetElem
      IF((iElem.LE.nElems).AND.(iElem.GT.0)) THEN
        IF(iDelay.LE.tempDelay) THEN
          pcount(iDelay) = pcount(iDelay) + 1
          RadialWeighting%ClonePartNum(iDelay) = pcount(iDelay)
          ClonedParticles(pcount(iDelay),iDelay)%PartState(1) = CloneData(1,iPart)
          ClonedParticles(pcount(iDelay),iDelay)%PartState(2) = CloneData(2,iPart)
          ClonedParticles(pcount(iDelay),iDelay)%PartState(3) = CloneData(3,iPart)
          ClonedParticles(pcount(iDelay),iDelay)%PartState(4) = CloneData(4,iPart)
          ClonedParticles(pcount(iDelay),iDelay)%PartState(5) = CloneData(5,iPart)
          ClonedParticles(pcount(iDelay),iDelay)%PartState(6) = CloneData(6,iPart)
          ClonedParticles(pcount(iDelay),iDelay)%Species = INT(CloneData(7,iPart))
          ClonedParticles(pcount(iDelay),iDelay)%Element = INT(CloneData(8,iPart))
          ClonedParticles(pcount(iDelay),iDelay)%lastPartPos(1:3) = CloneData(1:3,iPart)
          IF (UseDSMC) THEN
            IF ((CollisMode.GT.1).AND.(usevMPF) .AND. (DSMC%ElectronicModel) ) THEN
              ClonedParticles(pcount(iDelay),iDelay)%PartStateIntEn(1) = CloneData(10,iPart)
              ClonedParticles(pcount(iDelay),iDelay)%PartStateIntEn(2) = CloneData(11,iPart)
              ClonedParticles(pcount(iDelay),iDelay)%PartStateIntEn(3) = CloneData(12,iPart)
              ClonedParticles(pcount(iDelay),iDelay)%WeightingFactor   = CloneData(13,iPart)
            ELSE IF ( (CollisMode .GT. 1) .AND. (usevMPF) ) THEN
              ClonedParticles(pcount(iDelay),iDelay)%PartStateIntEn(1) = CloneData(10,iPart)
              ClonedParticles(pcount(iDelay),iDelay)%PartStateIntEn(2) = CloneData(11,iPart)
              ClonedParticles(pcount(iDelay),iDelay)%WeightingFactor   = CloneData(12,iPart)
            ELSE IF ( (CollisMode .GT. 1) .AND. (DSMC%ElectronicModel) ) THEN
              ClonedParticles(pcount(iDelay),iDelay)%PartStateIntEn(1) = CloneData(10,iPart)
              ClonedParticles(pcount(iDelay),iDelay)%PartStateIntEn(2) = CloneData(11,iPart)
              ClonedParticles(pcount(iDelay),iDelay)%PartStateIntEn(3) = CloneData(12,iPart)
            ELSE IF (CollisMode.GT.1) THEN
              ClonedParticles(pcount(iDelay),iDelay)%PartStateIntEn(1) = CloneData(10,iPart)
              ClonedParticles(pcount(iDelay),iDelay)%PartStateIntEn(2) = CloneData(11,iPart)
            ELSE IF (usevMPF) THEN
              ClonedParticles(pcount(iDelay),iDelay)%WeightingFactor = CloneData(10,iPart)
            END IF
          ELSE IF (usevMPF) THEN
              ClonedParticles(pcount(iDelay),iDelay)%WeightingFactor = CloneData(10,iPart)
          END IF
          IF (UseDSMC.AND.(DSMC%NumPolyatomMolecs.GT.0)) THEN
            IF (SpecDSMC(ClonedParticles(pcount(iDelay),iDelay)%Species)%PolyatomicMol) THEN
              iPolyatMole = SpecDSMC(ClonedParticles(pcount(iDelay),iDelay)%Species)%SpecToPolyArray
              ALLOCATE(ClonedParticles(pcount(iDelay),iDelay)%VibQuants(1:PolyatomMolDSMC(iPolyatMole)%VibDOF))
              ClonedParticles(pcount(iDelay),iDelay)%VibQuants(1:PolyatomMolDSMC(iPolyatMole)%VibDOF) &
                = VibQuantData(1:PolyatomMolDSMC(iPolyatMole)%VibDOF,iPart)
            END IF
          END IF
          IF (UseDSMC.AND.DSMC%ElectronicModel.AND.DSMC%ElectronicDistrModel)  THEN
            IF (.NOT.((SpecDSMC(ClonedParticles(pcount(iDelay),iDelay)%Species)%InterID.EQ.4) &
                .OR.SpecDSMC(ClonedParticles(pcount(iDelay),iDelay)%Species)%FullyIonized)) THEN 
              ALLOCATE(ClonedParticles(pcount(iDelay),iDelay)%DistriFunc( &
                      1:SpecDSMC(ClonedParticles(pcount(iDelay),iDelay)%Species)%MaxElecQuant))
              ClonedParticles(pcount(iDelay),iDelay)%DistriFunc(1:SpecDSMC(ClonedParticles(pcount(iDelay),iDelay)%Species)%MaxElecQuant) &
                = ElecDistriData(1:SpecDSMC(ClonedParticles(pcount(iDelay),iDelay)%Species)%MaxElecQuant,iPart)
            END IF
          END IF
          IF (UseDSMC.AND.DSMC%DoAmbipolarDiff)  THEN
            IF (Species(ClonedParticles(pcount(iDelay),iDelay)%Species)%ChargeIC.GT.0.0) THEN      
              ALLOCATE(ClonedParticles(pcount(iDelay),iDelay)%AmbiPolVelo(1:3))
              ClonedParticles(pcount(iDelay),iDelay)%AmbiPolVelo(1:3) = AD_Data(1:3,iPart)
            END IF
          END IF
        END IF
      END IF
    END DO
  ELSE
    SWRITE(*,*) 'Read-in of cloned particles complete. No clones detected.'
  END IF

END SUBROUTINE RestartClones


SUBROUTINE MacroscopicRestart()
!===================================================================================================================================
!>
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_io_hdf5
USE MOD_HDF5_Input    ,ONLY: OpenDataFile,CloseDataFile,ReadArray,GetDataSize
USE MOD_HDF5_Input    ,ONLY: nDims,HSize,File_ID
USE MOD_Restart_Vars  ,ONLY: MacroRestartFileName, MacroRestartValues
USE MOD_Mesh_Vars     ,ONLY: offsetElem, nElems
USE MOD_Particle_Vars ,ONLY: nSpecies
USE MOD_Macro_Restart ,ONLY: MacroRestart_InsertParticles
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                           :: nVar_HDF5, iVar, iSpec, iElem
REAL, ALLOCATABLE                 :: ElemData_HDF5(:,:)
!===================================================================================================================================

SWRITE(UNIT_stdOut,*) 'Using macroscopic values from file: ',TRIM(MacroRestartFileName)

CALL OpenDataFile(MacroRestartFileName,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.,communicatorOpt=MPI_COMM_WORLD)

CALL GetDataSize(File_ID,'ElemData',nDims,HSize,attrib=.FALSE.)
nVar_HDF5=INT(HSize(1),4)

ALLOCATE(MacroRestartValues(1:nElems,1:nSpecies+1,1:DSMC_NVARS))
MacroRestartValues = 0.

ALLOCATE(ElemData_HDF5(1:nVar_HDF5,1:nElems))
! Associate construct for integer KIND=8 possibility
ASSOCIATE (&
  nVar_HDF5  => INT(nVar_HDF5,IK) ,&
  offsetElem => INT(offsetElem,IK),&
  nElems     => INT(nElems,IK)    )
  CALL ReadArray('ElemData',2,(/nVar_HDF5,nElems/),offsetElem,2,RealArray=ElemData_HDF5(:,:))
END ASSOCIATE

iVar = 1
DO iSpec = 1, nSpecies
  DO iElem = 1, nElems
    MacroRestartValues(iElem,iSpec,:) = ElemData_HDF5(iVar:iVar-1+DSMC_NVARS,iElem)
  END DO
  iVar = iVar + DSMC_NVARS
END DO

CALL MacroRestart_InsertParticles()

DEALLOCATE(MacroRestartValues)
DEALLOCATE(ElemData_HDF5)

END SUBROUTINE MacroscopicRestart
#endif /*PARTICLES*/


#if USE_HDG
SUBROUTINE RecomputeLambda(t)
!===================================================================================================================================
! The lambda-solution is stored per side, however, the side-list is computed with the OLD domain-decomposition. To allow for
! a change in the load-distribution, number of used cores, etc,... lambda has to be recomputed ONCE
!===================================================================================================================================
! MODULES
USE MOD_DG_Vars,                 ONLY: U
USE MOD_PreProc
USE MOD_HDG,                     ONLY: HDG
USE MOD_TimeDisc_Vars,           ONLY: iter
#ifdef PARTICLES
USE MOD_PICDepo,                 ONLY: Deposition
#if USE_MPI
USE MOD_Particle_MPI,            ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
#endif /*USE_MPI*/
#endif /*PARTICLES*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)       :: t
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================

#ifdef PARTICLES
! Deposition of particles
CALL Deposition()
#endif /*PARTICLES*/

! recompute fields
! EM field
CALL HDG(t,U,iter)

END SUBROUTINE RecomputeLambda
#endif /*USE_HDG*/

SUBROUTINE FinalizeRestart()
!===================================================================================================================================
! Finalizes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Restart_Vars,ONLY:Vdm_GaussNRestart_GaussN,RestartInitIsDone,DoMacroscopicRestart
! IMPLICIT VARIABLE HANDLINGDGInitIsDone
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
SDEALLOCATE(Vdm_GaussNRestart_GaussN)
RestartInitIsDone = .FALSE.
! Avoid performing a macroscopic restart during an automatic load balance restart
DoMacroscopicRestart = .FALSE.
END SUBROUTINE FinalizeRestart

END MODULE MOD_Restart
