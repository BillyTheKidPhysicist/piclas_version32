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

MODULE MOD_HDF5_Output_State
!===================================================================================================================================
! Add comments please!
!===================================================================================================================================
! MODULES
USE MOD_io_HDF5
USE MOD_HDF5_output
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------

INTERFACE WriteStateToHDF5
  MODULE PROCEDURE WriteStateToHDF5
END INTERFACE

PUBLIC :: WriteStateToHDF5
#if defined(PARTICLES)
PUBLIC :: WriteIMDStateToHDF5
#endif /*PARTICLES*/
!===================================================================================================================================

CONTAINS


SUBROUTINE WriteStateToHDF5(MeshFileName,OutputTime,PreviousTime)
!===================================================================================================================================
! Subroutine to write the solution U to HDF5 format
! Is used for postprocessing and for restart
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_DG_Vars                ,ONLY: U
USE MOD_Globals_Vars           ,ONLY: ProjectName
USE MOD_Mesh_Vars              ,ONLY: offsetElem,nGlobalElems,nGlobalUniqueSides,nUniqueSides,offsetSide
USE MOD_Equation_Vars          ,ONLY: StrVarNames
USE MOD_Restart_Vars           ,ONLY: RestartFile,DoInitialAutoRestart
#ifdef PARTICLES
USE MOD_DSMC_Vars              ,ONLY: RadialWeighting
USE MOD_PICDepo_Vars           ,ONLY: OutputSource,PartSource
USE MOD_Particle_Sampling_Vars ,ONLY: UseAdaptive
USE MOD_SurfaceModel_Vars      ,ONLY: nPorousBC
USE MOD_Particle_Boundary_Vars ,ONLY: DoBoundaryParticleOutputHDF5, PartBound
USE MOD_Dielectric_Vars        ,ONLY: DoDielectricSurfaceCharge
USE MOD_Particle_Tracking_Vars ,ONLY: CountNbrOfLostParts,TotalNbrOfMissingParticlesSum,NbrOfNewLostParticlesTotal
USE MOD_Mesh_Tools             ,ONLY: GetCNElemID
USE MOD_Particle_Analyze_Vars  ,ONLY: nSpecAnalyze
USE MOD_Particle_Analyze_Tools ,ONLY: CalcNumPartsOfSpec
USE MOD_HDF5_Output_Particles  ,ONLY: WriteNodeSourceExtToHDF5,WriteClonesToHDF5,WriteVibProbInfoToHDF5,WriteAdaptiveWallTempToHDF5
USE MOD_HDF5_Output_Particles  ,ONLY: WriteAdaptiveInfoToHDF5,WriteParticleToHDF5,WriteBoundaryParticleToHDF5
USE MOD_HDF5_Output_Particles  ,ONLY: WriteLostParticlesToHDF5
#endif /*PARTICLES*/
#ifdef PP_POIS
USE MOD_Equation_Vars          ,ONLY: E,Phi
#endif /*PP_POIS*/
#if USE_HDG
USE MOD_HDG_Vars               ,ONLY: lambda, nGP_face
#if PP_nVar==1
USE MOD_Equation_Vars          ,ONLY: E
#elif PP_nVar==3
USE MOD_Equation_Vars          ,ONLY: B
#else
USE MOD_Equation_Vars          ,ONLY: E,B
#endif /*PP_nVar*/
USE MOD_Mesh_Vars              ,ONLY: nSides
USE MOD_Utils                  ,ONLY: QuickSortTwoArrays
USE MOD_Mesh_Vars              ,ONLY: MortarType,SideToElem,MortarInfo
USE MOD_Mesh_Vars              ,ONLY: firstMortarInnerSide,lastMortarInnerSide
USE MOD_Mesh_Vars              ,ONLY: lastMPISide_MINE,lastInnerSide
USE MOD_Mappings               ,ONLY: CGNS_SideToVol2
USE MOD_Utils                  ,ONLY: Qsort1DoubleInt1PInt
#if USE_MPI
USE MOD_MPI_Vars               ,ONLY: OffsetMPISides_rec,nNbProcs,nMPISides_rec,nbProc,RecRequest_U,SendRequest_U
USE MOD_MPI                    ,ONLY: StartReceiveMPIData,StartSendMPIData,FinishExchangeMPIData
#endif /*USE_MPI*/
USE MOD_Mesh_Vars              ,ONLY: GlobalUniqueSideID
#ifdef PARTICLES
USE MOD_PICInterpolation_Vars  ,ONLY: useAlgebraicExternalField,AlgebraicExternalField
USE MOD_Analyze_Vars           ,ONLY: AverageElectricPotential
USE MOD_Mesh_Vars              ,ONLY: Elem_xGP
USE MOD_HDG_Vars               ,ONLY: UseBRElectronFluid,BRAutomaticElectronRef,RegionElectronRef
USE MOD_Particle_Analyze_Vars  ,ONLY: CalcElectronIonDensity,CalcElectronTemperature
USE MOD_Particle_Analyze_Tools ,ONLY: AllocateElectronIonDensityCell,AllocateElectronTemperatureCell
USE MOD_Particle_Analyze_Tools ,ONLY: CalculateElectronIonDensityCell,CalculateElectronTemperatureCell
USE MOD_HDF5_Output_Particles  ,ONLY: AddBRElectronFluidToPartSource
#endif /*PARTICLES*/
#endif /*USE_HDG*/
USE MOD_Analyze_Vars           ,ONLY: OutputTimeFixed
USE MOD_Mesh_Vars              ,ONLY: DoWriteStateToHDF5
USE MOD_StringTools            ,ONLY: set_formatting,clear_formatting
USE MOD_HDF5_Input             ,ONLY: ReadArray
#if (PP_nVar==8)
USE MOD_HDF5_Output_Fields     ,ONLY: WritePMLDataToHDF5
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
CHARACTER(LEN=*),INTENT(IN)    :: MeshFileName
REAL,INTENT(IN)                :: OutputTime
REAL,INTENT(IN),OPTIONAL       :: PreviousTime
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255)             :: FileName
#ifdef PARTICLES
CHARACTER(LEN=255),ALLOCATABLE :: LocalStrVarNames(:)
INTEGER(KIND=IK)               :: nVar
REAL                           :: NumSpec(nSpecAnalyze)
INTEGER(KIND=IK)               :: SimNumSpec(nSpecAnalyze)
#endif /*PARTICLES*/
REAL                           :: StartT,EndT

#ifdef PP_POIS
REAL                           :: Utemp(PP_nVar,0:PP_N,0:PP_N,0:PP_N,PP_nElems)
#elif USE_HDG
#if PP_nVar==1
REAL                           :: Utemp(1:4,0:PP_N,0:PP_N,0:PP_N,PP_nElems)
#elif PP_nVar==3
REAL                           :: Utemp(1:3,0:PP_N,0:PP_N,0:PP_N,PP_nElems)
#else /*PP_nVar=4*/
REAL                           :: Utemp(1:7,0:PP_N,0:PP_N,0:PP_N,PP_nElems)
#endif /*PP_nVar==1*/
#else
#ifndef maxwell
REAL,ALLOCATABLE               :: Utemp(:,:,:,:,:)
#endif /*not maxwell*/
#endif /*PP_POIS*/
REAL                           :: OutputTime_loc
REAL                           :: PreviousTime_loc
INTEGER(KIND=IK)               :: PP_nVarTmp
LOGICAL                        :: usePreviousTime_loc
#if USE_HDG
INTEGER                        :: iSide
INTEGER                        :: SideID,iGlobSide,iLocSide,iLocSide_NB,iMortar,nMortars,MortarSideID
INTEGER,ALLOCATABLE            :: SortedUniqueSides(:),GlobalUniqueSideID_tmp(:)
LOGICAL,ALLOCATABLE            :: OutputSide(:)
REAL,ALLOCATABLE               :: SortedLambda(:,:,:)          ! lambda, ((PP_N+1)^2,nSides)
INTEGER                        :: SortedOffset,SortedStart,SortedEnd,p,q,r,rr,pq(1:2)
INTEGER                        :: SideID_start, SideID_end,iNbProc,SendID
REAL,ALLOCATABLE               :: iLocSides(:,:,:)          ! iLocSides, ((PP_N+1)^2,nSides)
#ifdef PARTICLES
INTEGER                        :: i,j,k,iElem
#endif /*PARTICLES*/
#endif /*USE_HDG*/
!===================================================================================================================================
#ifdef EXTRAE
CALL extrae_eventandcounters(int(9000001), int8(3))
#endif /*EXTRAE*/
! set local variables for output and previous times
IF(OutputTimeFixed.GE.0.0)THEN ! use fixed output time supplied by user
  SWRITE(UNIT_StdOut,'(A,ES25.14E3,A2)',ADVANCE='NO')' (WriteStateToHDF5 for fixed output time :',OutputTimeFixed,') '
  OutputTime_loc   = OutputTimeFixed
  PreviousTime_loc = OutputTimeFixed
ELSE
  OutputTime_loc   = OutputTime
  IF(PRESENT(PreviousTime))PreviousTime_loc = PreviousTime
END IF

#ifdef PARTICLES
! Output lost particles if 1. lost during simulation     : NbrOfNewLostParticlesTotal > 0
!                          2. went missing during restart: TotalNbrOfMissingParticlesSum > 0
IF(CountNbrOfLostParts)THEN
  IF((NbrOfNewLostParticlesTotal.GT.0).OR.(TotalNbrOfMissingParticlesSum.GT.0))THEN
   CALL WriteLostParticlesToHDF5(MeshFileName,OutputTime_loc)
  END IF ! (NbrOfNewLostParticlesTotal.GT.0).OR.(TotalNbrOfMissingParticlesSum.GT.0)
END IF
! Output total number of particles here, if DoWriteStateToHDF5=F. Otherwise the info will be displayed at the end of this routine
IF(.NOT.DoWriteStateToHDF5)THEN
  ! Check if the total number of particles has already been determined
  IF(.NOT.GlobalNbrOfParticlesUpdated) CALL CalcNumPartsOfSpec(NumSpec,SimNumSpec,.FALSE.,.TRUE.)
  ! Output total number of particles here as the end of this routine will not be reached
  SWRITE(UNIT_StdOut,'(A,ES16.7)') "#Particles : ", REAL(nGlobalNbrOfParticles)
END IF ! .NOT.DoWriteStateToHDF5
#endif /*PARTICLES*/

! Check if state file creation should be skipped
IF(.NOT.DoWriteStateToHDF5) RETURN

SWRITE(UNIT_stdOut,'(a)',ADVANCE='NO')' WRITE STATE TO HDF5 FILE '
#if USE_MPI
StartT=MPI_WTIME()
#else
CALL CPU_TIME(StartT)
#endif


! Generate skeleton for the file with all relevant data on a single proc (MPIRoot)
FileName=TRIM(TIMESTAMP(TRIM(ProjectName)//'_State',OutputTime_loc))//'.h5'
SWRITE(UNIT_stdOut,'(a)',ADVANCE='NO') '['//TRIM(FileName)//'] ...'
RestartFile=Filename
#if USE_HDG
#if PP_nVar==1
IF(MPIRoot) CALL GenerateFileSkeleton('State',4,StrVarNames,MeshFileName,OutputTime_loc)
#elif PP_nVar==3
IF(MPIRoot) CALL GenerateFileSkeleton('State',3,StrVarNames,MeshFileName,OutputTime_loc)
#else
IF(MPIRoot) CALL GenerateFileSkeleton('State',7,StrVarNames,MeshFileName,OutputTime_loc)
#endif
#else
IF(MPIRoot) CALL GenerateFileSkeleton('State',PP_nVar,StrVarNames,MeshFileName,OutputTime_loc)
#endif /*USE_HDG*/
! generate nextfile info in previous output file
usePreviousTime_loc=.FALSE.

IF(PRESENT(PreviousTime).AND.(.NOT.DoInitialAutoRestart))THEN
  usePreviousTime_loc=.TRUE.
  IF(MPIRoot .AND. PreviousTime_loc.LT.OutputTime_loc) CALL GenerateNextFileInfo('State',OutputTime_loc,PreviousTime_loc)
END IF

! Reopen file and write DG solution
#if USE_MPI
CALL MPI_BARRIER(MPI_COMM_WORLD,iError)
#endif

! Associate construct for integer KIND=8 possibility
PP_nVarTmp = INT(PP_nVar,IK)
ASSOCIATE (&
      N                 => INT(PP_N,IK)               ,&
      nGlobalElems      => INT(nGlobalElems,IK)       ,&
      PP_nElems         => INT(PP_nElems,IK)          ,&
      offsetElem        => INT(offsetElem,IK)         ,&
      offsetSide        => INT(offsetSide,IK)         ,&
      nUniqueSides      => INT(nUniqueSides,IK)       ,&
      nGlobalUniqueSides=> INT(nGlobalUniqueSides,IK)  )

  ! Write DG solution ----------------------------------------------------------------------------------------------------------------
  !nVal=nGlobalElems  ! For the MPI case this must be replaced by the global number of elements (sum over all procs)
  ! Store the Solution of the Maxwell-Poisson System
#ifdef PP_POIS
  ALLOCATE(Utemp(1:PP_nVar,0:N,0:N,0:N,PP_nElems))
#if (PP_nVar==8)
  Utemp(8,:,:,:,:)=Phi(1,:,:,:,:)
  Utemp(1:3,:,:,:,:)=E(1:3,:,:,:,:)
  Utemp(4:7,:,:,:,:)=U(4:7,:,:,:,:)

  CALL GatheredWriteArray(FileName,create=.FALSE.,&
      DataSetName='DG_Solution', rank=5,&
      nValGlobal=(/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
      nVal=      (/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
      offset=    (/0_IK       , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
      collective=.TRUE.,RealArray=Utemp)

  CALL GatheredWriteArray(FileName,create=.FALSE.,&
      DataSetName='DG_SolutionE', rank=5,&
      nValGlobal=(/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
      nVal=      (/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
      offset=    (/0_IK       , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
      collective=.TRUE.,RealArray=U)

  !CALL WriteArrayToHDF5('DG_SolutionPhi',nVal,5,(/4_IK,N+1,N+1,N+1,PP_nElems/) &
  !,offsetElem,5,existing=.FALSE.,RealArray=Phi)
  ! missing addiontal attributes and data preparation
  CALL GatheredWriteArray(FileName,create=.FALSE.,&
      DataSetName='DG_SolutionPhi', rank=5,&
      nValGlobal=(/4_IK , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
      nVal=      (/4_IK , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
      offset=    (/0_IK , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
      collective=.TRUE.,RealArray=Phi)
#endif /*(PP_nVar==8)*/
  ! Store the solution of the electrostatic-poisson system
#if (PP_nVar==4)
  Utemp(1,:,:,:,:)=Phi(1,:,:,:,:)
  Utemp(2:4,:,:,:,:)=E(1:3,:,:,:,:)

  CALL GatheredWriteArray(FileName,create=.FALSE.,&
      DataSetName='DG_Solution', rank=5,&
      nValGlobal=(/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
      nVal=      (/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
      offset=    (/0_IK       , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
      collective=.TRUE.,RealArray=Utemp)

  CALL GatheredWriteArray(FileName,create=.FALSE.,&
      DataSetName='DG_SolutionE', rank=5,&
      nValGlobal=(/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
      nVal=      (/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
      offset=    (/0_IK       , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
      collective=.TRUE.,RealArray=U)

  CALL GatheredWriteArray(FileName,create=.FALSE.,&
      DataSetName='DG_SolutionPhi', rank=5,&
      nValGlobal=(/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
      nVal=      (/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
      offset=    (/0_IK       , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
      collective=.TRUE.,RealArray=Phi)
#endif /*(PP_nVar==4)*/
  DEALLOCATE(Utemp)
#elif USE_HDG

  ! Store lambda solution in sorted order by ascending global unique side ID
#if USE_MPI
  IF(nProcessors.GT.1)THEN
    ! 0. Store true/false info for each side if it should be written to h5 by each process
    ALLOCATE(OutputSide(1:nSides))
    OutputSide=.FALSE.

    ! 1. Flag BC and inner sides
    OutputSide(1:lastInnerSide) = .TRUE.

    ! 2. Flag MINE/YOUR sides that are sent to other procs and if their rank is larger this proc, it writes the data
    DO SendID = 1, 2
      DO iNbProc=1,nNbProcs
        IF(nMPISides_rec(iNbProc,SendID).GT.0)THEN
          SideID_start=OffsetMPISides_rec(iNbProc-1,SendID)+1
          SideID_end  =OffsetMPISides_rec(iNbProc,SendID)
          IF(nbProc(iNbProc).GT.myrank)THEN
            OutputSide(SideID_start:SideID_end) = .TRUE.
          END IF ! nbProc(iNbProc)
        END IF
      END DO !iProc=1,nNBProcs
    END DO ! SendID = 1, 2

  ! Exchange iLocSides from master to slaves: Send MINE, receive YOUR direction
    ALLOCATE(iLocSides(PP_nVar,nGP_face,nSides))
    iLocSides = -100.
    DO iSide = 1, nSides
      iLocSides(:,:,iSide) = REAL(SideToElem(S2E_LOC_SIDE_ID,iSide))

      iLocSide_NB = SideToElem(S2E_NB_LOC_SIDE_ID,iSide)

      ! Check real small mortar side (when the same proc has both the big an one or more small side connected elements)
      IF(MortarType(1,iSide).EQ.0.AND.iLocSide_NB.NE.-1) iLocSides(:,:,iSide) = REAL(iLocSide_NB)

      ! is small virtual mortar side is encountered and no NB iLocSide is given
      IF(MortarType(1,iSide).EQ.0.AND.iLocSide_NB.EQ.-1)THEN
        ! check all my big mortar sides and find the one to which the small virtual is connected
        Check1: DO MortarSideID=firstMortarInnerSide,lastMortarInnerSide
          nMortars=MERGE(4,2,MortarType(1,MortarSideID).EQ.1)
          DO iMortar=1,nMortars
            SideID= MortarInfo(MI_SIDEID,iMortar,MortarType(2,MortarSideID)) !small SideID
            IF(iSide.EQ.SideID)THEN
              iLocSide = SideToElem(S2E_LOC_SIDE_ID,MortarSideID)
              IF(iLocSide.NE.-1)THEN ! MINE side (big mortar)
                iLocSides(:,:,iSide) = REAL(iLocSide)
              ELSE
                CALL abort(__STAMP__,'This big mortar side must be master')
              END IF !iLocSide.NE.-1
              EXIT Check1
            END IF ! iSide.EQ.SideID
          END DO !iMortar
        END DO Check1 !MortarSideID
      END IF ! MortarType(1,iSide).EQ.0
    END DO
    CALL StartReceiveMPIData(1,iLocSides,1,nSides, RecRequest_U,SendID=1) ! Receive YOUR
    CALL StartSendMPIData(   1,iLocSides,1,nSides,SendRequest_U,SendID=1) ! Send MINE
    CALL FinishExchangeMPIData(SendRequest_U,RecRequest_U,SendID=1)
  END IF ! nProcessors.GT.1
#endif /*USE_MPI*/

  ! Get mapping from side IDs to globally sorted unique side IDs
  ALLOCATE(SortedUniqueSides(1:nSides))
  ALLOCATE(GlobalUniqueSideID_tmp(1:nSides))
  SortedUniqueSides=0
  DO iSide = 1, nSides
    SortedUniqueSides(iSide)=iSide
  END DO ! iSide = 1, nSides

  ! Create tmp array which will be sorted
  GlobalUniqueSideID_tmp = GlobalUniqueSideID
  CALL QuickSortTwoArrays(1,nSides,GlobalUniqueSideID_tmp(1:nSides),SortedUniqueSides(1:nSides))
  DEALLOCATE(GlobalUniqueSideID_tmp)

  ! Fill array with lambda values in global unique side sorted order
  ALLOCATE(SortedLambda(PP_nVar,nGP_face,nSides))
  SortedLambda = HUGE(1.)
  DO iGlobSide = 1, nSides
    ! Set side ID in processor local list
    iSide = SortedUniqueSides(iGlobSide)

    ! Skip sides that are not processed by the current proc
    IF(nProcessors.GT.1)THEN
      IF(.NOT.OutputSide(iSide)) CYCLE
    END IF ! nProcessors.GT.1

    IF(iSide.GT.lastMPISide_MINE)THEN
      iLocSide = NINT(iLocSides(1,1,iSide))
    ELSE
      iLocSide = SideToElem(S2E_LOC_SIDE_ID,iSide)
    END IF ! iSide.GT.lastMPISide_MINE

    !master element
    !iLocSide = SideToElem(S2E_LOC_SIDE_ID,iSide)
    IF(iLocSide.NE.-1)THEN ! MINE side
      DO q=0,PP_N
        DO p=0,PP_N
          pq=CGNS_SideToVol2(PP_N,p,q,iLocSide)
          r  = q    *(PP_N+1)+p    +1
          rr = pq(2)*(PP_N+1)+pq(1)+1
          SortedLambda(:,r:r,iGlobSide) = lambda(:,rr:rr,iSide)
        END DO
      END DO !p,q
      CYCLE
    END IF !iLocSide.NE.-1

    ! neighbour element (e.g. small mortar sides when one proc has both the large and one or more small side connected elements)
    iLocSide_NB = SideToElem(S2E_NB_LOC_SIDE_ID,iSide)
    IF(iLocSide_NB.NE.-1)THEN ! YOUR side
      DO q=0,PP_N
        DO p=0,PP_N
          pq = CGNS_SideToVol2(PP_N,p,q,iLocSide_NB)
          r  = q    *(PP_N+1)+p    +1
          rr = pq(2)*(PP_N+1)+pq(1)+1
          SortedLambda(:,r:r,iGlobSide) = lambda(:,rr:rr,iSide)
        END DO
      END DO !p,q
      CYCLE
    END IF !iLocSide_NB.NE.-1

    ! is small virtual mortar side is encountered and no NB iLocSide is given
    IF(MortarType(1,iSide).EQ.0.AND.iLocSide_NB.EQ.-1)THEN
      ! check all my big mortar sides and find the one to which the small virtual is connected
      Check2: DO MortarSideID=firstMortarInnerSide,lastMortarInnerSide
        nMortars=MERGE(4,2,MortarType(1,MortarSideID).EQ.1)
        !locSide=MortarType(2,MortarSideID)
        DO iMortar=1,nMortars
          SideID= MortarInfo(MI_SIDEID,iMortar,MortarType(2,MortarSideID)) !small SideID
          IF(iSide.EQ.SideID)THEN
            iLocSide = SideToElem(S2E_LOC_SIDE_ID,MortarSideID)
            IF(iLocSide.NE.-1)THEN ! MINE side (big mortar)
              DO q=0,PP_N
                DO p=0,PP_N
                  pq=CGNS_SideToVol2(PP_N,p,q,iLocSide)
                  r  = q    *(PP_N+1)+p    +1
                  rr = pq(2)*(PP_N+1)+pq(1)+1
                  SortedLambda(:,r:r,iGlobSide) = lambda(:,rr:rr,iSide)
                END DO
              END DO !p,q
            ELSE
              CALL abort(__STAMP__,'This big mortar side must be master')
            END IF !iLocSide.NE.-1
            EXIT Check2
          END IF ! iSide.EQ.SideID
        END DO !iMortar
      END DO Check2 !MortarSideID
    END IF ! MortarType(1,iSide).EQ.0
  END DO ! iGlobSide = 1, nSides

  ! Deallocate temporary arrays
  DEALLOCATE(SortedUniqueSides)
  IF(nProcessors.GT.1) DEALLOCATE(iLocSides)


  ! Get offset and min/max index in sorted list
  SortedStart = 1
  SortedEnd   = nSides

  IF(nProcessors.GT.1)THEN
    SortedOffset=HUGE(1)
    DO iSide = 1, nSides
      ! Get local offset of global unique sides: the smallest global unique side ID
      IF(OutputSide(iSide))THEN
        IF(GlobalUniqueSideID(iSide).LT.SortedOffset) SortedOffset = GlobalUniqueSideID(iSide)
      ELSE
        ! the sum of non-output sides gives the beginning number of output sides for each proc
        SortedStart = SortedStart +1
      END IF ! OutputSide(iSide))
    END DO
    SortedOffset = SortedOffset-1
    DEALLOCATE(OutputSide)
  ELSE
    SortedOffset = 0
  END IF ! nProcessors.GT.1

  ASSOCIATE( nOutputSides => INT(SortedEnd-SortedStart+1,IK) ,&
        SortedOffset => INT(SortedOffset,IK)            ,&
        SortedStart  => INT(SortedStart,IK)             ,&
        SortedEnd    => INT(SortedEnd,IK)                )
    CALL GatheredWriteArray(FileName,create=.FALSE.,&
        DataSetName = 'DG_SolutionLambda', rank=3,&
        nValGlobal  = (/PP_nVarTmp , nGP_face , nGlobalUniqueSides/) , &
        nVal        = (/PP_nVarTmp , nGP_face , nOutputSides/)       , &
        offset      = (/0_IK       , 0_IK     , SortedOffset/)       , &
        collective  = .TRUE.                                         , &
        RealArray   = SortedLambda(:,:,SortedStart:SortedEnd))
  END ASSOCIATE
  DEALLOCATE(SortedLambda)

  CALL GatheredWriteArray(FileName,create=.FALSE.,&
      DataSetName='DG_SolutionU', rank=5,&
      nValGlobal=(/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
      nVal=      (/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
      offset=    (/0_IK       , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
      collective=.TRUE., RealArray=U)
#if (PP_nVar==1)

#ifdef PARTICLES
  IF(useAlgebraicExternalField.AND.AlgebraicExternalField.EQ.1)THEN
    DO iElem=1,PP_nElems
      DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
        ASSOCIATE( Ue => AverageElectricPotential ,&
              xe => 2.4e-2                        ,&
              x  => Elem_xGP(1,i,j,k,iElem))
          Utemp(1,i,j,k,iElem) = U(1,i,j,k,iElem) - x * Ue / xe
          Utemp(2,i,j,k,iElem) = E(1,i,j,k,iElem) + Ue / xe
        END ASSOCIATE
      END DO; END DO; END DO !i,j,k
    END DO !iElem
    Utemp(3:4,:,:,:,:) = E(2:3,:,:,:,:)
  ELSE
#endif /*PARTICLES*/
    Utemp(1,:,:,:,:)   = U(1,:,:,:,:)
    Utemp(2:4,:,:,:,:) = E(1:3,:,:,:,:)
#ifdef PARTICLES
  END IF
#endif /*PARTICLES*/

  CALL GatheredWriteArray(FileName,create=.FALSE.,&
      DataSetName='DG_Solution', rank=5,&
      nValGlobal=(/4_IK , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
      nVal=      (/4_IK , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
      offset=    (/0_IK , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
      collective=.TRUE., RealArray=Utemp)

#elif (PP_nVar==3)
  Utemp(1:3,:,:,:,:)=B(1:3,:,:,:,:)
  !CALL WriteArrayToHDF5('DG_Solution',nVal,5,(/PP_nVar,N+1,N+1,N+1,PP_nElems/) &
  !,offsetElem,5,existing=.TRUE.,RealArray=Utemp)
  CALL GatheredWriteArray(FileName,create=.FALSE.,&
      DataSetName='DG_Solution', rank=5,&
      nValGlobal=(/3_IK , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
      nVal=      (/3_IK , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
      offset=    (/0_IK , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
      collective=.TRUE., RealArray=Utemp)
#else /*(PP_nVar==4)*/
  Utemp(1,:,:,:,:)=U(4,:,:,:,:)
  Utemp(2:4,:,:,:,:)=E(1:3,:,:,:,:)
  Utemp(5:7,:,:,:,:)=B(1:3,:,:,:,:)

  CALL GatheredWriteArray(FileName,create=.FALSE.,&
      DataSetName='DG_Solution', rank=5,&
      nValGlobal=(/7_IK , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
      nVal=      (/7_IK , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
      offset=    (/0_IK , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
      collective=.TRUE., RealArray=Utemp)
#endif /*(PP_nVar==1)*/
#else
  CALL GatheredWriteArray(FileName,create=.FALSE.,&
      DataSetName='DG_Solution', rank=5,&
      nValGlobal=(/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
      nVal=      (/PP_nVarTmp , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
      offset=    (/0_IK       , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
      collective=.TRUE.,RealArray=U)
#endif /*PP_POIS*/


#ifdef PARTICLES
  ! output of last source term
#if USE_MPI
  CALL MPI_BARRIER(MPI_COMM_WORLD,iError)
#endif /*USE_MPI*/
  IF(OutPutSource) THEN
#if USE_HDG
    ! Add BR electron fluid density to PartSource for output to state.h5
    IF(UseBRElectronFluid) CALL AddBRElectronFluidToPartSource()
#endif /*USE_HDG*/
    ! output of pure current and density
    ! not scaled with epsilon0 and c_corr
    nVar=4_IK
    ALLOCATE(LocalStrVarNames(1:nVar))
    LocalStrVarNames(1)='CurrentDensityX'
    LocalStrVarNames(2)='CurrentDensityY'
    LocalStrVarNames(3)='CurrentDensityZ'
    LocalStrVarNames(4)='ChargeDensity'
    IF(MPIRoot)THEN
      CALL OpenDataFile(FileName,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
      CALL WriteAttributeToHDF5(File_ID,'VarNamesSource',INT(nVar,4),StrArray=LocalStrVarnames)
      CALL CloseDataFile()
    END IF
    ASSOCIATE(&
        CNElemIDStart  => INT(GetCNElemID(INT(offsetElem          ,4)+1),IK) ,&
        CNElemIDEnd    => INT(GetCNElemID(INT(offsetElem+PP_nElems,4)  ),IK) )
      CALL GatheredWriteArray(FileName,create=.FALSE.,&
          DataSetName='DG_Source', rank=5,  &
          nValGlobal=(/nVar , N+1_IK , N+1_IK , N+1_IK , nGlobalElems/) , &
          nVal=      (/nVar , N+1_IK , N+1_IK , N+1_IK , PP_nElems/)    , &
          offset=    (/0_IK , 0_IK   , 0_IK   , 0_IK   , offsetElem/)   , &
          collective=.TRUE.,RealArray=PartSource(:,:,:,:,CNElemIDStart:CNElemIDEnd))
    END ASSOCIATE

    DEALLOCATE(LocalStrVarNames)
  END IF
#endif /*PARTICLES*/

END ASSOCIATE

#ifdef PARTICLES
CALL WriteParticleToHDF5(FileName)
IF(DoBoundaryParticleOutputHDF5) THEN
  IF (usePreviousTime_loc) THEN
    CALL WriteBoundaryParticleToHDF5(MeshFileName,OutputTime_loc,PreviousTime_loc)
  ELSE
    CALL WriteBoundaryParticleToHDF5(MeshFileName,OutputTime_loc)
  END IF
END IF
IF(UseAdaptive.OR.(nPorousBC.GT.0)) CALL WriteAdaptiveInfoToHDF5(FileName)
CALL WriteVibProbInfoToHDF5(FileName)
IF(RadialWeighting%PerformCloning) CALL WriteClonesToHDF5(FileName)
IF (ANY(PartBound%UseAdaptedWallTemp)) CALL WriteAdaptiveWallTempToHDF5(FileName)
#if USE_MPI
CALL MPI_BARRIER(MPI_COMM_WORLD,iError)
#endif /*USE_MPI*/
#endif /*PARTICLES*/

#if USE_LOADBALANCE
! Write 'ElemTime' to a separate container in the state.h5 file
CALL WriteElemDataToSeparateContainer(FileName,ElementOut,'ElemTime')
#endif /*USE_LOADBALANCE*/

#if defined(PARTICLES) && USE_HDG
! Write 'ElectronDensityCell' and 'ElectronTemperatureCell' to a separate container in the state.h5 file
! (for special read-in and conversion to kinetic electrons)
IF(UseBRElectronFluid) THEN
  ! Check if electron density is already calculated in each cell
  IF(.NOT.CalcElectronIonDensity)THEN
    CALL AllocateElectronIonDensityCell()
    CALL CalculateElectronIonDensityCell()
  END IF
  CALL WriteElemDataToSeparateContainer(FileName,ElementOut,'ElectronDensityCell')

  ! Check if electron temperature is already calculated in each cell
  IF(.NOT.CalcElectronTemperature)THEN
    CALL AllocateElectronTemperatureCell()
    CALL CalculateElectronTemperatureCell()
  END IF
  CALL WriteElemDataToSeparateContainer(FileName,ElementOut,'ElectronTemperatureCell')
END IF
! Automatically obtain the reference parameters (from a fully kinetic simulation), store them in .h5 state
IF(BRAutomaticElectronRef)THEN
  IF(MPIRoot)THEN ! only root writes the container
    CALL OpenDataFile(FileName,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
    CALL WriteArrayToHDF5( DataSetName = 'RegionElectronRef' , rank = 2 , &
                           nValGlobal  = (/1_IK , 3_IK/)     , &
                           nVal        = (/1_IK , 3_IK/)     , &
                           offset      = (/0_IK , 0_IK/)     , &
                           collective  = .FALSE., RealArray = RegionElectronRef(1:3,1))
    CALL CloseDataFile()
  END IF !MPIRoot
END IF ! BRAutomaticElectronRef
#endif /*defined(PARTICLES) && USE_HDG*/

! Adjust values before WriteAdditionalElemData() is called
CALL ModifyElemData(mode=1)

! Write all 'ElemData' arrays to a single container in the state.h5 file
CALL WriteAdditionalElemData(FileName,ElementOut)

! Adjust values after WriteAdditionalElemData() is called
CALL ModifyElemData(mode=2)

#if (PP_nVar==8)
CALL WritePMLDataToHDF5(FileName)
#endif

#ifdef PARTICLES
! Write NodeSourceExt (external charge density) field to HDF5 file
IF(DoDielectricSurfaceCharge) CALL WriteNodeSourceExtToHDF5(OutputTime_loc)
#endif /*PARTICLES*/

EndT=PICLASTIME()
SWRITE(UNIT_stdOut,'(A,F0.3,A)',ADVANCE='YES')'DONE  [',EndT-StartT,'s]'
SWRITE(UNIT_StdOut,'(A,ES16.7)') "#Particles : ", REAL(nGlobalNbrOfParticles)

#ifdef EXTRAE
CALL extrae_eventandcounters(int(9000001), int8(0))
#endif /*EXTRAE*/
END SUBROUTINE WriteStateToHDF5


SUBROUTINE ModifyElemData(mode)
!===================================================================================================================================
!> Modify ElemData fields before/after WriteAdditionalElemData() is called
!===================================================================================================================================
! MODULES
USE MOD_TimeDisc_Vars         ,ONLY: Time
USE MOD_Restart_Vars          ,ONLY: RestartTime
#ifdef PARTICLES
USE MOD_Globals               ,ONLY: abort
USE MOD_Particle_Analyze_Vars ,ONLY: CalcCoupledPower,PCouplSpec
USE MOD_Particle_Vars         ,ONLY: nSpecies,Species
#endif /*PARTICLES*/
#if USE_MPI
USE MOD_Globals
#endif /*USE_MPI*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(IN) :: mode ! 1: before WriteAdditionalElemData() is called
!                          ! 2: after WriteAdditionalElemData() is called
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
#ifdef PARTICLES
REAL          :: timediff
INTEGER       :: iSpec
#else
INTEGER       :: dummy ! dummy variable for compiler warning suppression
#endif /*PARTICLES*/
!===================================================================================================================================

IF(ABS(Time-RestartTime).LE.0.0) RETURN

#ifdef PARTICLES
IF(mode.EQ.1)THEN
  timediff = 1.0 / (Time-RestartTime)
ELSEIF(mode.EQ.2)THEN
  timediff = (Time-RestartTime)
ELSE
  CALL abort( __STAMP__,'ModifyElemData: mode must be 1 or 2')
END IF ! mode.EQ.1

! Set coupled power to particles if output of coupled power is active
IF (CalcCoupledPower.AND.(timediff.GT.0.)) THEN
  DO iSpec = 1, nSpecies
    IF(ABS(Species(iSpec)%ChargeIC).GT.0.0)THEN
      PCouplSpec(iSpec)%DensityAvgElem = PCouplSpec(iSpec)%DensityAvgElem * timediff
    END IF
  END DO
END IF
#endif /*PARTICLES*/

#if !defined(PARTICLES)
! Suppress compiler warning
RETURN
dummy=mode
#endif /*!(PARTICLES)*/

END SUBROUTINE ModifyElemData


#if defined(PARTICLES)
SUBROUTINE WriteIMDStateToHDF5()
!===================================================================================================================================
! Write the particles data aquired from an IMD *.chkpt file to disk and abort the program
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Particle_Vars ,ONLY: IMDInputFile,IMDTimeScale,IMDLengthScale,IMDNumber
USE MOD_Mesh_Vars     ,ONLY: MeshFile
USE MOD_Restart_Vars  ,ONLY: DoRestart
#if USE_MPI
USE MOD_MPI           ,ONLY: FinalizeMPI
#endif /*USE_MPI*/
USE MOD_ReadInTools   ,ONLY: PrintOption
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255) :: tempStr
REAL               :: t,tFuture,IMDtimestep
INTEGER            :: iSTATUS,IMDanalyzeIter
!===================================================================================================================================
IF(.NOT.DoRestart)THEN
  IF(IMDTimeScale.GT.0.0)THEN
    SWRITE(UNIT_StdOut,'(A)')'   IMD: calc physical time in seconds for which the IMD *.chkpt file is defined.'
    ! calc physical time in seconds for which the IMD *.chkpt file is defined
    ! t = IMDanalyzeIter * IMDtimestep * IMDTimeScale * IMDNumber
    IMDtimestep=0.0
    CALL GetParameterFromFile(IMDInputFile,'timestep'   , TempStr ,DelimiterSymbolIN=' ',CommentSymbolIN='#')
    CALL str2real(TempStr,IMDtimestep,iSTATUS)
    IF(iSTATUS.NE.0)THEN
      CALL abort(&
      __STAMP__&
      ,'Could not find "timestep" in '//TRIM(IMDInputFile)//' for IMDtimestep!')
    END IF

    IMDanalyzeIter=0
    CALL GetParameterFromFile(IMDInputFile,'checkpt_int', TempStr ,DelimiterSymbolIN=' ',CommentSymbolIN='#')
    CALL str2int(TempStr,IMDanalyzeIter,iSTATUS)
    IF(iSTATUS.NE.0)THEN
      CALL abort(&
      __STAMP__&
      ,'Could not find "checkpt_int" in '//TRIM(IMDInputFile)//' for IMDanalyzeIter!')
    END IF
    CALL PrintOption('IMDtimestep'    , 'OUTPUT' , RealOpt=IMDtimestep)
    CALL PrintOption('IMDanalyzeIter' , 'OUTPUT' , IntOpt=IMDanalyzeIter)
    CALL PrintOption('IMDTimeScale'   , 'OUTPUT' , RealOpt=IMDTimeScale)
    CALL PrintOption('IMDLengthScale' , 'OUTPUT' , RealOpt=IMDLengthScale)
    CALL PrintOption('IMDNumber'      , 'OUTPUT' , IntOpt=IMDNumber)
    t = REAL(IMDanalyzeIter) * IMDtimestep * IMDTimeScale * REAL(IMDNumber)
    CALL PrintOption('t'              , 'OUTPUT' , RealOpt=t)
    SWRITE(UNIT_StdOut,'(A,ES25.14E3,A,F15.3,A)')     '   Calculated time t :',t,' (',t*1e12,' ps)'

    tFuture=t
    CALL WriteStateToHDF5(TRIM(MeshFile),t,tFuture)
    SWRITE(UNIT_StdOut,'(A)')'   Particles: StateFile (IMD MD data) created. Terminating successfully!'
#if USE_MPI
    CALL FinalizeMPI()
    CALL MPI_FINALIZE(iERROR)
    IF(iERROR.NE.0)THEN
      CALL abort(&
      __STAMP__&
      , ' MPI_FINALIZE(iERROR) returned non-zero integer value',iERROR)
    END IF
#endif /*USE_MPI*/
    STOP 0 ! terminate successfully
  ELSE
    CALL abort(&
    __STAMP__&
    , ' IMDLengthScale.LE.0.0 which is not allowed')
  END IF
END IF
END SUBROUTINE WriteIMDStateToHDF5
#endif /*PARTICLES*/


#if USE_LOADBALANCE || defined(PARTICLES)
SUBROUTINE WriteElemDataToSeparateContainer(FileName,ElemList,ElemDataName)
!===================================================================================================================================
!> Similar to WriteAdditionalElemData() but only writes one of the fields to a separate container
!> ----------------
!> Write additional data for analyze purpose to HDF5.
!> The data is taken from a lists, containing either pointers to data arrays or pointers
!> to functions to generate the data, along with the respective varnames.
!>
!> Two options are available:
!>    1. WriteAdditionalElemData:
!>       Element-wise scalar data, e.g. the timestep or indicators.
!>       The data is collected in a single array and written out in one step.
!>       DO NOT MISUSE NODAL DATA FOR THIS! IT WILL DRASTICALLY INCREASE FILE SIZE AND SLOW DOWN IO!
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_Mesh_Vars        ,ONLY: nElems
USE MOD_HDF5_Input       ,ONLY: ReadArray
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars ,ONLY: ElemTime,ElemTime_tmp,NullifyElemTime
USE MOD_Restart_Vars     ,ONLY: DoRestart
USE MOD_Mesh_Vars        ,ONLY: nGlobalElems,offsetelem
#endif /*USE_LOADBALANCE*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
CHARACTER(LEN=255),INTENT(IN)        :: FileName
TYPE(tElementOut),POINTER,INTENT(IN) :: ElemList !< Linked list of arrays to write to file
CHARACTER(LEN=*),INTENT(IN)          :: ElemDataName
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255)                   :: StrVarNames
REAL,ALLOCATABLE                     :: ElemData(:,:)
INTEGER                              :: nVar,iElem
TYPE(tElementOut),POINTER            :: e
!===================================================================================================================================

IF(.NOT. ASSOCIATED(ElemList)) RETURN

! Allocate variable names and data array
ALLOCATE(ElemData(1,nElems))

! Fill the arrays
nVar = 0
e=>ElemList
DO WHILE(ASSOCIATED(e))
  StrVarNames=e%VarName
  IF(StrVarNames.EQ.TRIM(ElemDataName))THEN
    nVar=nVar+1
    IF(ASSOCIATED(e%RealArray))    ElemData(nVar,:)=e%RealArray(1:nElems)
    IF(ASSOCIATED(e%RealScalar))   ElemData(nVar,:)=e%RealScalar
    IF(ASSOCIATED(e%IntArray))     ElemData(nVar,:)=REAL(e%IntArray(1:nElems))
    IF(ASSOCIATED(e%IntScalar))    ElemData(nVar,:)=REAL(e%IntScalar)
    IF(ASSOCIATED(e%LongIntArray)) ElemData(nVar,:)=REAL(e%LongIntArray(1:nElems))
    IF(ASSOCIATED(e%LogArray)) THEN
      DO iElem=1,nElems
        IF(e%LogArray(iElem))THEN
          ElemData(nVar,iElem)=1.
        ELSE
          ElemData(nVar,iElem)=0.
        END IF
      END DO ! iElem=1,PP_nElems
    END IF
    IF(ASSOCIATED(e%eval))       CALL e%eval(ElemData(nVar,:)) ! function fills elemdata
    EXIT
  END IF ! StrVarNames.EQ.TRIM(ElemDataName)
  e=>e%next
END DO

IF(nVar.NE.1) CALL abort(&
    __STAMP__&
    ,'WriteElemDataToSeparateContainer: Array not found in ElemData = '//TRIM(ElemDataName))

#if USE_LOADBALANCE
! Check if ElemTime is all zeros and if this is a restart (save the old values)
NullifyElemTime=.FALSE.
IF((MAXVAL(ElemData).LE.0.0)          .AND.& ! Restart
    DoRestart                         .AND.& ! Restart
    (TRIM(ElemDataName).EQ.'ElemTime').AND.& ! only for ElemTime array
    ALLOCATED(ElemTime_tmp))THEN             ! only allocated when not starting simulation from zero
  ! Additionally, store old values in ElemData container
  ElemTime = ElemTime_tmp
  NullifyElemTime=.TRUE. ! Set array to 0. after ElemData is written (but before ElemTime is measured again)

  ! Write 'ElemTime' container
  ASSOCIATE (&
        nVar         => INT(nVar,IK)         ,&
        nGlobalElems => INT(nGlobalElems,IK) ,&
        PP_nElems    => INT(PP_nElems,IK)    ,&
        offsetElem   => INT(offsetElem,IK)   )
    CALL GatheredWriteArray(FileName,create = .FALSE.,&
                            DataSetName     = TRIM(ElemDataName), rank = 2,  &
                            nValGlobal      = (/nVar,nGlobalElems/),&
                            nVal            = (/nVar,PP_nElems   /),&
                            offset          = (/0_IK,offsetElem  /),&
                            collective      = .TRUE.,RealArray        = ElemTime_tmp)
  END ASSOCIATE

ELSE
  ASSOCIATE (&
        nVar         => INT(nVar,IK)         ,&
        nGlobalElems => INT(nGlobalElems,IK) ,&
        PP_nElems    => INT(PP_nElems,IK)    ,&
        offsetElem   => INT(offsetElem,IK)   )
    CALL GatheredWriteArray(FileName,create = .FALSE.,&
                            DataSetName     = TRIM(ElemDataName), rank = 2,  &
                            nValGlobal      = (/nVar,nGlobalElems/),&
                            nVal            = (/nVar,PP_nElems   /),&
                            offset          = (/0_IK,offsetElem  /),&
                            collective      = .TRUE.,RealArray        = ElemData)
  END ASSOCIATE
END IF ! (MAXVAL(ElemData).LE.0.0).AND.DoRestart.AND.(TRIM(ElemDataName).EQ.'ElemTime')
#endif /*USE_LOADBALANCE*/

DEALLOCATE(ElemData)

END SUBROUTINE WriteElemDataToSeparateContainer
#endif /*USE_LOADBALANCE || defined(PARTICLES)*/


SUBROUTINE WriteAdditionalElemData(FileName,ElemList)
!===================================================================================================================================
!> Write additional data for analyze purpose to HDF5.
!> The data is taken from a lists, containing either pointers to data arrays or pointers
!> to functions to generate the data, along with the respective varnames.
!>
!> Two options are available:
!>    1. WriteAdditionalElemData:
!>       Element-wise scalar data, e.g. the timestep or indicators.
!>       The data is collected in a single array and written out in one step.
!>       DO NOT MISUSE NODAL DATA FOR THIS! IT WILL DRASTICALLY INCREASE FILE SIZE AND SLOW DOWN IO!
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_Mesh_Vars        ,ONLY: offsetElem,nGlobalElems,nElems
USE MOD_LoadBalance_Vars ,ONLY: ElemTime,NullifyElemTime
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
CHARACTER(LEN=255),INTENT(IN)        :: FileName
TYPE(tElementOut),POINTER,INTENT(IN) :: ElemList !< Linked list of arrays to write to file
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255),ALLOCATABLE :: StrVarNames(:)
REAL,ALLOCATABLE               :: ElemData(:,:)
INTEGER                        :: nVar,iElem
TYPE(tElementOut),POINTER      :: e
!===================================================================================================================================

IF(.NOT. ASSOCIATED(ElemList)) RETURN

! Count the additional variables
nVar = 0
e=>ElemList
DO WHILE(ASSOCIATED(e))
  nVar=nVar+1
  e=>e%next
END DO

! Allocate variable names and data array
ALLOCATE(StrVarNames(nVar))
ALLOCATE(ElemData(nVar,nElems))

! Fill the arrays
nVar = 0
e=>ElemList
DO WHILE(ASSOCIATED(e))
  nVar=nVar+1
  StrVarNames(nVar)=e%VarName
  IF(ASSOCIATED(e%RealArray))    ElemData(nVar,:)=e%RealArray(1:nElems)
  IF(ASSOCIATED(e%RealScalar))   ElemData(nVar,:)=e%RealScalar
  IF(ASSOCIATED(e%IntArray))     ElemData(nVar,:)=REAL(e%IntArray(1:nElems))
  IF(ASSOCIATED(e%IntScalar))    ElemData(nVar,:)=REAL(e%IntScalar)
  IF(ASSOCIATED(e%LongIntArray)) ElemData(nVar,:)=REAL(e%LongIntArray(1:nElems))
  IF(ASSOCIATED(e%LogArray)) THEN
    DO iElem=1,nElems
      IF(e%LogArray(iElem))THEN
        ElemData(nVar,iElem)=1.
      ELSE
        ElemData(nVar,iElem)=0.
      END IF
    END DO ! iElem=1,PP_nElems
  END IF
  IF(ASSOCIATED(e%eval))       CALL e%eval(ElemData(nVar,:)) ! function fills elemdata
  e=>e%next
END DO

IF(MPIRoot)THEN
  CALL OpenDataFile(FileName,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
  CALL WriteAttributeToHDF5(File_ID,'VarNamesAdd',nVar,StrArray=StrVarNames)
  CALL CloseDataFile()
END IF

ASSOCIATE (&
      nVar         => INT(nVar,IK)         ,&
      nGlobalElems => INT(nGlobalElems,IK) ,&
      PP_nElems    => INT(PP_nElems,IK)    ,&
      offsetElem   => INT(offsetElem,IK)   )
  CALL GatheredWriteArray(FileName,create = .FALSE.,&
                          DataSetName     = 'ElemData', rank = 2,  &
                          nValGlobal      = (/nVar,nGlobalElems/),&
                          nVal            = (/nVar,PP_nElems   /),&
                          offset          = (/0_IK,offsetElem  /),&
                          collective      = .TRUE.,RealArray = ElemData)
END ASSOCIATE
DEALLOCATE(ElemData,StrVarNames)

! Check if ElemTime is to be nullified (required after user-restart)
! After writing the old ElemTime values to disk, the array must be nullified (because they correspond to the restart file, which
! might have been created with a totally different processor number and distribution)
IF(NullifyElemTime) ElemTime=0.

END SUBROUTINE WriteAdditionalElemData


END MODULE MOD_HDF5_Output_State
