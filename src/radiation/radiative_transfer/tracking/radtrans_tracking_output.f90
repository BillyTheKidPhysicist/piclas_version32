!==================================================================================================================================
! Copyright (c) 2018 - 2019 Marcel Pfeiffer
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

MODULE MOD_Photon_TrackingOutput
!===================================================================================================================================
! Module for the main radiation transport routines
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
PUBLIC :: WritePhotonSurfSampleToHDF5,WritePhotonVolSampleToHDF5
!===================================================================================================================================

CONTAINS

SUBROUTINE WritePhotonVolSampleToHDF5()
!===================================================================================================================================
! Writes Radiation values to HDF5
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_Mesh_Vars            ,ONLY: nElems,MeshFile,offSetElem,sJ
USE MOD_Globals_Vars         ,ONLY: ProjectName
USE MOD_RayTracing_Vars      ,ONLY: Ray,nVarRay,U_N_Ray,N_DG_Ray,PREF_VDM_Ray,N_DG_Ray_loc,N_Inter_Ray
USE MOD_RayTracing_Vars      ,ONLY: RayElemPassedEnergyLoc1st,RayElemPassedEnergyLoc2nd
USE MOD_RayTracing_Vars      ,ONLY: RaySecondaryVectorX,RaySecondaryVectorY,RaySecondaryVectorZ
USE MOD_HDF5_output          ,ONLY: GatheredWriteArray
#if USE_MPI
USE MOD_RayTracing_Vars      ,ONLY: RayElemPassedEnergy_Shared,RayElemOffset,RayElemPassedEnergyHO_Shared
#else
USE MOD_RayTracing_Vars      ,ONLY: RayElemPassedEnergy
#endif /*USE_MPI*/
USE MOD_io_HDF5
USE MOD_HDF5_output          ,ONLY: GenerateFileSkeleton
USE MOD_HDF5_Output_ElemData ,ONLY: WriteAdditionalElemData
USE MOD_Mesh_Vars            ,ONLY: offsetElem,nGlobalElems
USE MOD_ChangeBasis          ,ONLY: ChangeBasis3D
USE MOD_Interpolation_Vars ,ONLY: NodeType
USE MOD_Interpolation      ,ONLY: GetVandermonde
USE MOD_Mesh_Tools            ,ONLY: GetCNElemID
USE MOD_Particle_Mesh_Vars      ,ONLY: ElemVolume_Shared
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
CHARACTER(LEN=255)                  :: FileName
INTEGER                             :: iElem,iGlobalElem,iCNElem,Nloc,k,l,m
CHARACTER(LEN=255), ALLOCATABLE     :: StrVarNames(:)
REAL                                :: U(nVarRay,0:Ray%NMax,0:Ray%NMax,0:Ray%NMax,PP_nElems)
#if USE_MPI
INTEGER                             :: NlocOffset
#endif /*USE_MPI*/
REAL                                :: J_N(1,0:PP_N,0:PP_N,0:PP_N)
REAL                                :: J_Nmax(1:1,0:Ray%NMax,0:Ray%NMax,0:Ray%NMax)
REAL                                :: IntegrationWeight
REAL                                :: Vdm_GaussN_Nloc(0:PP_N,0:Ray%NMax)    !< for interpolation to Analyze points (from NodeType nodes to Gauss-Lobatto nodes)
!===================================================================================================================================
SWRITE(UNIT_stdOut,'(a)',ADVANCE='NO') ' WRITE Radiation TO HDF5 FILE...'

ALLOCATE(RayElemPassedEnergyLoc1st(1:nElems))
ALLOCATE(RayElemPassedEnergyLoc2nd(1:nElems))
ALLOCATE(RaySecondaryVectorX(1:nElems))
ALLOCATE(RaySecondaryVectorY(1:nElems))
ALLOCATE(RaySecondaryVectorZ(1:nElems))
RayElemPassedEnergyLoc1st=-1.0
RayElemPassedEnergyLoc2nd=-1.0
RaySecondaryVectorX=-1.0
RaySecondaryVectorY=-1.0
RaySecondaryVectorZ=-1.0
CALL AddToElemData(ElementOut,'RayElemPassedEnergy1st',RealArray=RayElemPassedEnergyLoc1st)
CALL AddToElemData(ElementOut,'RayElemPassedEnergy2nd',RealArray=RayElemPassedEnergyLoc2nd)
CALL AddToElemData(ElementOut,'RaySecondaryVectorX'   ,RealArray=RaySecondaryVectorX)
CALL AddToElemData(ElementOut,'RaySecondaryVectorY'   ,RealArray=RaySecondaryVectorY)
CALL AddToElemData(ElementOut,'RaySecondaryVectorZ'   ,RealArray=RaySecondaryVectorZ)

! Copy data from shared array
ALLOCATE(N_DG_Ray_loc(1:nElems))
DO iElem = 1, nElems
  N_DG_Ray_loc(iElem) = N_DG_Ray(iElem + offsetElem)
END DO ! iElem = 1, nElems
CALL AddToElemData(ElementOut,'Nloc',IntArray=N_DG_Ray_loc)

ALLOCATE(StrVarNames(1:nVarRay))
StrVarNames(1)='RayElemPassedEnergy1st'
StrVarNames(2)='RayElemPassedEnergy2nd'

! Generate skeleton for the file with all relevant data on a single proc (MPIRoot)
FileName=TRIM(ProjectName)//'_RadiationVolState.h5'
IF(MPIRoot) CALL GenerateFileSkeleton('RadiationVolState',nVarRay,StrVarNames,TRIM(MeshFile),0.,FileNameIn=FileName,NIn=Ray%NMax,NodeType_in=Ray%NodeType)
#if USE_MPI
  CALL MPI_BARRIER(MPI_COMM_WORLD,iError)
#endif
#if USE_MPI
CALL ExchangeRayVolInfo()
#endif /*USE_MPI*/

! p-refinement: Interpolate lower degree to higher degree (other way around would require model=T)
CALL GetVandermonde(PP_N, NodeType, Ray%NMax, Ray%NodeType, Vdm_GaussN_Nloc, modal=.FALSE.)

#if USE_MPI
ASSOCIATE( RayElemPassedEnergy => RayElemPassedEnergy_Shared )
#endif /*USE_MPI*/
  DO iElem=1,PP_nElems
    iGlobalElem = iElem+offSetElem
    iCNElem = GetCNElemID(iGlobalElem)

    ! 1. Elem-constant data
    ! Primary energy
    RayElemPassedEnergyLoc1st(iElem) = RayElemPassedEnergy(1,iGlobalElem) / ElemVolume_Shared(iCNElem)
    ! Secondary energy
    RayElemPassedEnergyLoc2nd(iElem) = RayElemPassedEnergy(2,iGlobalElem) / ElemVolume_Shared(iCNElem)
    ! Check if secondary energy is greater than zero
    IF(RayElemPassedEnergyLoc2nd(iElem).GT.0.0)THEN
      IF(RayElemPassedEnergy(6,iGlobalElem).LE.0.0) CALL abort(__STAMP__,'Secondary ray counter is zero but energy is not!')
      ! x-, y- and z-direction of secondary energy
      RaySecondaryVectorX(iElem) = RayElemPassedEnergy(3,iGlobalElem) / RayElemPassedEnergy(6,iGlobalElem)
      RaySecondaryVectorY(iElem) = RayElemPassedEnergy(4,iGlobalElem) / RayElemPassedEnergy(6,iGlobalElem)
      RaySecondaryVectorZ(iElem) = RayElemPassedEnergy(5,iGlobalElem) / RayElemPassedEnergy(6,iGlobalElem)
    ELSE
      RaySecondaryVectorX(iElem) = 0.
      RaySecondaryVectorY(iElem) = 0.
      RaySecondaryVectorZ(iElem) = 0.
    END IF ! RayElemPassedEnergyLoc2nd(iElem).GT.0

    ! 2. Variable polynomial degree data
    Nloc = N_DG_Ray(iElem)
    !U_N_Ray(iElem)%U(1:1,:,:,:) = RayElemPassedEnergy(1,iGlobalElem)
    !U_N_Ray(iElem)%U(2:2,:,:,:) = RayElemPassedEnergy(2,iGlobalElem)
#if USE_MPI
    IF(nProcessors.GT.1)THEN
      ! Get data from shared array
      NlocOffset = (Nloc+1)**3
      ASSOCIATE( i => RayElemOffset(iGlobalElem))
        U_N_Ray(iElem)%U(1,:,:,:) = RESHAPE(RayElemPassedEnergyHO_Shared(1, i+1:i+NlocOffset), (/Nloc+1, Nloc+1, Nloc+1/))
        U_N_Ray(iElem)%U(2,:,:,:) = RESHAPE(RayElemPassedEnergyHO_Shared(2, i+1:i+NlocOffset), (/Nloc+1, Nloc+1, Nloc+1/))
      END ASSOCIATE
    END IF ! nProcessors.GT.1
#endif /*USE_MPI*/
    IF(Nloc.EQ.Ray%Nmax)THEN
      U(:,:,:,:,iElem) = U_N_Ray(iElem)%U(:,:,:,:)
    ELSE
      CALL ChangeBasis3D(nVarRay, Nloc, Ray%NMax, PREF_VDM_Ray(Nloc,Ray%NMax)%Vdm, U_N_Ray(iElem)%U(:,:,:,:), U(:,:,:,:,iElem))
    END IF ! Nloc.Eq.Nmax

    ! Apply integration weights and the Jacobian
    ! Interpolate the Jacobian to the analyze grid: be careful we interpolate the inverse of the inverse of the Jacobian ;-)
    J_N(1,0:PP_N,0:PP_N,0:PP_N)=1./sJ(:,:,:,iElem)
    CALL ChangeBasis3D(1,PP_N,Ray%NMax,Vdm_GaussN_Nloc,J_N(1:1,0:PP_N,0:PP_N,0:PP_N),J_Nmax(1:1,:,:,:))
    DO m=0,Ray%NMax
      DO l=0,Ray%NMax
        DO k=0,Ray%NMax
          IntegrationWeight = N_Inter_Ray(Ray%NMax)%wGP(k)*&
                              N_Inter_Ray(Ray%NMax)%wGP(l)*&
                              N_Inter_Ray(Ray%NMax)%wGP(m)*J_Nmax(1,k,l,m)
          U(1:2,k,l,m,iElem) = U(1:2,k,l,m,iElem) / IntegrationWeight
        END DO ! k
      END DO ! l
    END DO ! m

  END DO ! iElem=1,PP_nElems

  ! Associate construct for integer KIND=8 possibility
  ASSOCIATE (&
        nVarRay           => INT(nVarRay,IK)            ,&
        NMax              => INT(Ray%NMax,IK)           ,&
        nGlobalElems      => INT(nGlobalElems,IK)       ,&
        PP_nElems         => INT(PP_nElems,IK)          ,&
        offsetElem        => INT(offsetElem,IK)         )
    CALL GatheredWriteArray(FileName,create=.FALSE.,&
         DataSetName='DG_Solution', rank=5,&
         nValGlobal=(/nVarRay     , NMax+1_IK , NMax+1_IK , NMax+1_IK , nGlobalElems/) , &
         nVal=      (/nVarRay     , NMax+1_IK , NMax+1_IK , NMax+1_IK , PP_nElems/)    , &
         offset=    (/0_IK        , 0_IK      , 0_IK      , 0_IK      , offsetElem/)   , &
         collective=.TRUE.,RealArray=U)
  END ASSOCIATE
#if USE_MPI
END ASSOCIATE
#endif /*USE_MPI*/

! Write all 'ElemData' arrays to a single container in the state.h5 file
CALL WriteAdditionalElemData(FileName,ElementOut)

SWRITE(*,*) 'DONE'
END SUBROUTINE WritePhotonVolSampleToHDF5


SUBROUTINE WritePhotonSurfSampleToHDF5()
!===================================================================================================================================
!> write the final values of the surface sampling to a HDF5 state file
!> additional performs all the final required computations
!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_IO_HDF5
USE MOD_Globals_Vars           ,ONLY: ProjectName
USE MOD_Particle_Boundary_Vars ,ONLY: nComputeNodeSurfOutputSides,noutputsides, nSurfBC
USE MOD_Particle_Boundary_Vars ,ONLY: offsetComputeNodeSurfOutputSide, SurfBCName, nComputeNodeSurfSides
USE MOD_Particle_Boundary_Vars ,ONLY: SurfSide2GlobalSide, GlobalSide2SurfSide
USE MOD_HDF5_Output            ,ONLY: WriteAttributeToHDF5,WriteArrayToHDF5,WriteHDF5Header
USE MOD_Mesh_Vars              ,ONLY: MeshFile
USE MOD_Particle_Mesh_Vars     ,ONLY: SideInfo_Shared
USE MOD_MPI_Shared_Vars        ,ONLY: mySurfRank
#if USE_MPI
USE MOD_MPI_Shared_Vars        ,ONLY: MPI_COMM_LEADERS_SURF
USE MOD_Particle_Boundary_Vars ,ONLY: SurfSideArea_Shared,nSurfTotalSides
USE MOD_Photon_TrackingVars    ,ONLY: PhotonSampWall_Shared
#else
USE MOD_Photon_TrackingVars    ,ONLY: PhotonSampWall
USE MOD_Particle_Boundary_Vars ,ONLY: SurfSideArea
#endif /*USE_MPI*/
USE MOD_Particle_Boundary_Vars ,ONLY: nSurfSample, PartBound
!----------------------------------------------------------------------------------------------------------------------------------!
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255)                  :: FileString,Statedummy
CHARACTER(LEN=255)                  :: H5_Name
CHARACTER(LEN=4),PARAMETER          :: NodeTypeTemp = 'VISU'
CHARACTER(LEN=255),ALLOCATABLE      :: Str2DVarNames(:)
INTEGER                             :: GlobalSideID, iSurfSide, OutputCounter, SurfSideNb, p, q
INTEGER,PARAMETER                   :: nVar2D=3
REAL                                :: tstart,tend
REAL, ALLOCATABLE                   :: helpArray(:,:,:,:)
!===================================================================================================================================
#if USE_MPI
CALL ExchangeRadiationSurfData()
! Return if not a sampling leader
IF (MPI_COMM_LEADERS_SURF.EQ.MPI_COMM_NULL) RETURN
CALL MPI_BARRIER(MPI_COMM_LEADERS_SURF,iERROR)

! Return if no sampling sides
IF (nSurfTotalSides      .EQ.0) RETURN
#endif /*USE_MPI*/
IF (mySurfRank.EQ.0) THEN
  WRITE(UNIT_stdOut,'(a)',ADVANCE='NO')' WRITE Radiation SurfSTATE TO HDF5 FILE...'
  tstart=LOCALTIME()
END IF

FileString=TRIM(ProjectName)//'_RadiationSurfState.h5'

! Generate skeleton for the file with all relevant data on a single proc (MPIRoot)
#if USE_MPI
IF (mySurfRank.EQ.0) THEN
#endif /*USE_MPI*/
  CALL OpenDataFile(FileString,create=.TRUE.,single=.TRUE.,readOnly=.FALSE.)
  Statedummy = 'RadiationSurfState'
  ! Write file header
  CALL WriteHDF5Header(Statedummy,File_ID)
  CALL WriteAttributeToHDF5(File_ID , 'DSMC_nSurfSample' , 1       , IntegerScalar = nSurfSample        )
  CALL WriteAttributeToHDF5(File_ID , 'MeshFile'         , 1       , StrScalar     = (/TRIM(MeshFile)/) )
  CALL WriteAttributeToHDF5(File_ID , 'BC_Surf'          , nSurfBC , StrArray      = SurfBCName         )
  CALL WriteAttributeToHDF5(File_ID , 'N'                , 1       , IntegerScalar = nSurfSample        )
  CALL WriteAttributeToHDF5(File_ID , 'NodeType'         , 1       , StrScalar     = (/NodeTypeTemp/)   )
  CALL WriteAttributeToHDF5(File_ID , 'Time'             , 1       , RealScalar    = 0.                 )

  ALLOCATE(Str2DVarNames(1:nVar2D))
  ! fill varnames for total values
  Str2DVarNames(1) ='PhotonCount'
  Str2DVarNames(2) ='HeatFlux'
  Str2DVarNames(3) ='iBC'

  CALL WriteAttributeToHDF5(File_ID,'VarNamesSurface',nVar2D,StrArray=Str2DVarNames)

   CALL CloseDataFile()
  DEALLOCATE(Str2DVarNames)
#if USE_MPI
END IF
CALL MPI_BARRIER(MPI_COMM_LEADERS_SURF,iERROR)
CALL OpenDataFile(FileString,create=.FALSE.,single=.FALSE.,readOnly=.FALSE.,communicatorOpt=MPI_COMM_LEADERS_SURF)
#else
CALL OpenDataFile(FileString,create=.FALSE.,single=.FALSE.,readOnly=.FALSE.)
#endif /*USE_MPI*/


WRITE(H5_Name,'(A)') 'SurfaceData'
#if USE_MPI
ASSOCIATE(PhotonSampWall => PhotonSampWall_Shared ,&
          SurfSideArea   => SurfSideArea_Shared)
#endif

ASSOCIATE (&
      nSurfSample    => INT(nSurfSample                     , IK)  , &
      nGlobalSides   => INT(nOutputSides                    , IK)  , &
      LocalnBCSides  => INT(nComputeNodeSurfOutputSides     , IK)  , &
      offsetSurfSide => INT(offsetComputeNodeSurfOutputSide , IK)  , &
      nVar2D         => INT(nVar2D                          , IK))

  ALLOCATE(helpArray(nVar2D,1:nSurfSample,1:nSurfSample,LocalnBCSides))
  OutputCounter = 0
  !IF(myrank.eq.0) read*
  DO iSurfSide = 1,nComputeNodeSurfSides
    GlobalSideID = SurfSide2GlobalSide(SURF_SIDEID,iSurfSide)
    IF(SideInfo_Shared(SIDE_NBSIDEID,GlobalSideID).GT.0) THEN
      IF(GlobalSideID.LT.SideInfo_Shared(SIDE_NBSIDEID,GlobalSideID)) THEN
        SurfSideNb = GlobalSide2SurfSide(SURF_SIDEID,SideInfo_Shared(SIDE_NBSIDEID,GlobalSideID))
        PhotonSampWall(:,:,:,iSurfSide) = PhotonSampWall(:,:,:,iSurfSide) + PhotonSampWall(:,:,:,SurfSideNb)
      ELSE
        CYCLE
      END IF
    END IF
    OutputCounter = OutputCounter + 1
    helpArray(1,1:nSurfSample,1:nSurfSample,OutputCounter) = PhotonSampWall(1,1:nSurfSample,1:nSurfSample,iSurfSide)
    !  SurfaceArea should be changed to 1:SurfMesh%nSides if inner sampling sides exist...
    DO p = 1, nSurfSample
      DO q = 1, nSurfSample
        helpArray(2,p,q,OutputCounter) = PhotonSampWall(2,p,q,iSurfSide)/SurfSideArea(p,q,iSurfSide)
        helpArray(3,p,q,OutputCounter) = PartBound%MapToPartBC(SideInfo_Shared(SIDE_BCID,GlobalSideID))
      END DO ! q = 1, nSurfSample
    END DO ! p = 1, nSurfSample
  END DO
  CALL WriteArrayToHDF5(DataSetName=H5_Name  , rank=4      ,                                  &
                        nValGlobal =(/nVar2D , nSurfSample , nSurfSample , nGlobalSides/)   , &
                        nVal       =(/nVar2D , nSurfSample , nSurfSample , LocalnBCSides/)  , &
                        offset     =(/0_IK   , 0_IK        , 0_IK        , offsetSurfSide/) , &
                        collective =.FALSE.  ,                                                &
                        RealArray=helpArray(1:nVar2D,1:nSurfSample,1:nSurfSample,1:LocalnBCSides))
  DEALLOCATE(helpArray)
END ASSOCIATE

#if USE_MPI
END ASSOCIATE
#endif /*USE_MPI*/

CALL CloseDataFile()

IF (mySurfRank.EQ.0) THEN
  tend=LOCALTIME()
  WRITE(UNIT_stdOut,'(A,F0.3,A)',ADVANCE='YES')'DONE  [',tend-tstart,'s]'
END IF

END SUBROUTINE WritePhotonSurfSampleToHDF5

#if USE_MPI
SUBROUTINE ExchangeRadiationSurfData()
!===================================================================================================================================
! exchange the surface data
! only processes with samling sides in their halo region and the original process participate on the communication
! structure is similar to particle communication
! each process sends his halo-information directly to the origin process by use of a list, containing the surfsideids for sending
! the receiving process adds the new data to his own sides
!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Particle_Boundary_Vars ,ONLY: SurfOnNode, SurfMapping, nComputeNodeSurfTotalSides, GlobalSide2SurfSide, nSurfSample
USE MOD_Particle_MPI_Vars      ,ONLY: SurfSendBuf,SurfRecvBuf
USE MOD_Photon_TrackingVars    ,ONLY: PhotonSampWall, PhotonSampWall_Shared, PhotonSampWall_Shared_Win
USE MOD_MPI_Shared_Vars        ,ONLY: MPI_COMM_LEADERS_SURF, MPI_COMM_SHARED, nSurfLeaders,myComputeNodeRank,mySurfRank
USE MOD_MPI_Shared
!----------------------------------------------------------------------------------------------------------------------------------!
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                         :: MessageSize,nValues,iSurfSide,SurfSideID, SideID
INTEGER                         :: iPos,iProc,p,q
INTEGER                         :: RecvRequest(0:nSurfLeaders-1),SendRequest(0:nSurfLeaders-1)
!===================================================================================================================================
! nodes without sampling surfaces do not take part in this routine
IF (.NOT.SurfOnNode) RETURN

MessageSize = 2*nComputeNodeSurfTotalSides*(nSurfSample**2)
IF (myComputeNodeRank.EQ.0) THEN
  CALL MPI_REDUCE(PhotonSampWall, PhotonSampWall_Shared, MessageSize, MPI_DOUBLE_PRECISION, MPI_SUM, 0, MPI_COMM_SHARED, IERROR)
ELSE
  CALL MPI_REDUCE(PhotonSampWall, 0                    , MessageSize, MPI_DOUBLE_PRECISION, MPI_SUM, 0, MPI_COMM_SHARED, IERROR)
ENDIF

! Update
CALL BARRIER_AND_SYNC(PhotonSampWall_Shared_Win,MPI_COMM_SHARED)

! prepare buffers for surf leader communication
IF (myComputeNodeRank.EQ.0) THEN
  nValues = 2

  ! open receive buffer
  DO iProc = 0,nSurfLeaders-1
    ! ignore myself
    IF (iProc.EQ.mySurfRank) CYCLE

    ! Only open recv buffer if we are expecting sides from this leader node
    IF (SurfMapping(iProc)%nRecvSurfSides.EQ.0) CYCLE

    ! Message is sent on MPI_COMM_LEADERS_SURF, so rank is indeed iProc
    MessageSize = SurfMapping(iProc)%nRecvSurfSides * nValues
    CALL MPI_IRECV( SurfRecvBuf(iProc)%content                   &
                  , MessageSize                                  &
                  , MPI_DOUBLE_PRECISION                         &
                  , iProc                                        &
                  , 1209                                         &
                  , MPI_COMM_LEADERS_SURF                        &
                  , RecvRequest(iProc)                           &
                  , IERROR)
  END DO ! iProc

  ! build message
  DO iProc = 0,nSurfLeaders-1
    ! Ignore myself
    IF (iProc .EQ. mySurfRank) CYCLE
    ! Only assemble message if we are expecting sides to send to this leader node
    IF (SurfMapping(iProc)%nSendSurfSides.EQ.0) CYCLE

    ! Nullify everything
    iPos = 0
    SurfSendBuf(iProc)%content = 0.
    DO iSurfSide = 1,SurfMapping(iProc)%nSendSurfSides
      SideID     = SurfMapping(iProc)%SendSurfGlobalID(iSurfSide)
      SurfSideID = GlobalSide2SurfSide(SURF_SIDEID,SideID)
      ! Assemble message
      DO q = 1,nSurfSample
        DO p = 1,nSurfSample
        SurfSendBuf(iProc)%content(iPos+1:iPos+2) = PhotonSampWall_Shared(:,p,q,SurfSideID)
        iPos = iPos + 2
        END DO ! p=0,nSurfSample
      END DO ! q=0,nSurfSample
      PhotonSampWall_Shared(:,:,:,SurfSideID)=0.
    END DO ! iSurfSide = 1,SurfMapping(iProc)%nSendSurfSides
  END DO

  ! send message
  DO iProc = 0,nSurfLeaders-1
    ! ignore myself
    IF (iProc.EQ.mySurfRank) CYCLE
    ! Only open recv buffer if we are expecting sides from this leader node
    IF (SurfMapping(iProc)%nSendSurfSides.EQ.0) CYCLE

    ! Message is sent on MPI_COMM_LEADERS_SURF, so rank is indeed iProc
    MessageSize = SurfMapping(iProc)%nSendSurfSides * nValues
    CALL MPI_ISEND( SurfSendBuf(iProc)%content                   &
                  , MessageSize                                  &
                  , MPI_DOUBLE_PRECISION                         &
                  , iProc                                        &
                  , 1209                                         &
                  , MPI_COMM_LEADERS_SURF                        &
                  , SendRequest(iProc)                           &
                  , IERROR)
  END DO ! iProc

  ! Finish received number of sampling surfaces
  DO iProc = 0,nSurfLeaders-1
    ! ignore myself
    IF (iProc.EQ.mySurfRank) CYCLE

    IF (SurfMapping(iProc)%nSendSurfSides.NE.0) THEN
      CALL MPI_WAIT(SendRequest(iProc),MPIStatus,IERROR)
      IF (IERROR.NE.MPI_SUCCESS) CALL ABORT(__STAMP__,' MPI Communication error',IERROR)
    END IF

    IF (SurfMapping(iProc)%nRecvSurfSides.NE.0) THEN
      CALL MPI_WAIT(RecvRequest(iProc),MPIStatus,IERROR)
      IF (IERROR.NE.MPI_SUCCESS) CALL ABORT(__STAMP__,' MPI Communication error',IERROR)
    END IF
  END DO ! iProc

  ! add data do my list
  DO iProc = 0,nSurfLeaders-1
    ! ignore myself
    IF (iProc.EQ.mySurfRank) CYCLE
    ! Only open recv buffer if we are expecting sides from this leader node
    IF (SurfMapping(iProc)%nRecvSurfSides.EQ.0) CYCLE

    iPos=0
    DO iSurfSide = 1,SurfMapping(iProc)%nRecvSurfSides
      SideID     = SurfMapping(iProc)%RecvSurfGlobalID(iSurfSide)
      SurfSideID = GlobalSide2SurfSide(SURF_SIDEID,SideID)
      DO q = 1,nSurfSample
        DO p = 1,nSurfSample
          PhotonSampWall_Shared(:,p,q,SurfSideID) = PhotonSampWall_Shared(:,p,q,SurfSideID) &
                                                  + SurfRecvBuf(iProc)%content(iPos+1:iPos+2)
          iPos = iPos + 2
        END DO ! p=0,nSurfSample
      END DO ! q=0,nSurfSample
    END DO ! iSurfSide = 1,SurfMapping(iProc)%nRecvSurfSides
     ! Nullify buffer
    SurfRecvBuf(iProc)%content = 0.
  END DO ! iProc
END IF

CALL BARRIER_AND_SYNC(PhotonSampWall_Shared_Win         ,MPI_COMM_SHARED)

END SUBROUTINE ExchangeRadiationSurfData


!===================================================================================================================================
! Exchanges and add up the volume ray tracing data between all processes to have the global data available on each process
! 1. Exchange the low-order data
! 2. Exchange the high-order data
!===================================================================================================================================
SUBROUTINE ExchangeRayVolInfo()
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_MPI_Shared_Vars
USE MOD_MPI_Shared
USE MOD_RayTracing_Vars ,ONLY: RayElemPassedEnergy,RayElemPassedEnergy_Shared,RayElemPassedEnergy_Shared_Win,RayElemSize
USE MOD_RayTracing_Vars ,ONLY: nVarRay,RayElemPassedEnergyHO_Shared,RayElemPassedEnergyHO_Shared_Win,N_DG_Ray,U_N_Ray,RayElemOffset
USE MOD_Mesh_Vars       ,ONLY: nGlobalElems
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
INTEGER           :: MessageSize,offset,NlocOffset
INTEGER(KIND=8)   :: nGlobalEntries
REAL, ALLOCATABLE :: RayElemPassedEnergyHO(:,:) ! <
INTEGER           :: iElem,Nloc
CHARACTER(LEN=255):: hilf
!===================================================================================================================================
! Collect the information from the process-local shadow arrays in the compute-node shared array
MessageSize = RayElemSize*nGlobalElems

! 1. Exchange the low-order data
! Reduce data to each node leader
IF (myComputeNodeRank.EQ.0) THEN
  CALL MPI_REDUCE(RayElemPassedEnergy, RayElemPassedEnergy_Shared, MessageSize, MPI_DOUBLE_PRECISION, MPI_SUM, 0, MPI_COMM_SHARED, IERROR)
ELSE
  CALL MPI_REDUCE(RayElemPassedEnergy, 0                         , MessageSize, MPI_DOUBLE_PRECISION, MPI_SUM, 0, MPI_COMM_SHARED, IERROR)
ENDIF
CALL BARRIER_AND_SYNC(RayElemPassedEnergy_Shared_Win, MPI_COMM_SHARED)

! Synchronize data between node leaders with all-reduce
IF(nLeaderGroupProcs.GT.1)THEN
  IF(myComputeNodeRank.EQ.0)THEN
    CALL MPI_ALLREDUCE(MPI_IN_PLACE,RayElemPassedEnergy_Shared,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_LEADERS_SHARED,iError)
  END IF

  ! Synchronize data from node leaders to node workers
  CALL BARRIER_AND_SYNC(RayElemPassedEnergy_Shared_Win, MPI_COMM_SHARED)
END IF

! 2. Exchange the high-order data
! Only duplicate and reduce the data when more than one process are used
IF(nProcessors.GT.1)THEN

  nGlobalEntries = 0
  DO iElem = 1, nGlobalElems
    Nloc = N_DG_Ray(iElem)
    nGlobalEntries = nGlobalEntries + INT((Nloc+1)**3,8)
  END DO ! iElem = 1, nGlobalElems

  ! Sanity check
  IF(nGlobalEntries * INT(nVarRay,8).GT.INT(HUGE(1_4),8))THEN
    IF(MPIRoot)THEN
      WRITE(UNIT=hilf,FMT='(A,I0,A,I0)') "Number of entries in RayElemPassedEnergyHO(1:nVarRay,1:nGlobalEntries) "&
          ,nGlobalEntries * INT(nVarRay,8)," is larger than ",HUGE(1_4)
      CALL abort(__STAMP__,TRIM(hilf))
    END IF
  END IF

  ALLOCATE(RayElemPassedEnergyHO(nVarRay,nGlobalEntries))
  ALLOCATE(RayElemOffset(nGlobalElems))
  !> Shared arrays for high-order volume sampling
  CALL Allocate_Shared((/nVarRay,INT(nGlobalEntries,4)/),RayElemPassedEnergyHO_Shared_Win,RayElemPassedEnergyHO_Shared)
  CALL MPI_WIN_LOCK_ALL(0,RayElemPassedEnergyHO_Shared_Win,IERROR)
  CALL BARRIER_AND_SYNC(RayElemPassedEnergyHO_Shared_Win,MPI_COMM_SHARED)

  ! Store data in local array
  offset = 0
  DO iElem = 1, nGlobalElems
    Nloc = N_DG_Ray(iElem)
    NlocOffset = (Nloc+1)**3
    RayElemOffset(iElem) = offset
    RayElemPassedEnergyHO(1,offset+1:offset+NlocOffset) = RESHAPE(U_N_Ray(iElem)%U(1,:,:,:),(/(Nloc+1)**3/))
    RayElemPassedEnergyHO(2,offset+1:offset+NlocOffset) = RESHAPE(U_N_Ray(iElem)%U(2,:,:,:),(/(Nloc+1)**3/))
    offset = offset + NlocOffset
  END DO ! iElem = 1, nGlobalElems

  MessageSize = nVarRay * INT(nGlobalEntries,4)

  ! Reduce data to each node leader
  IF (myComputeNodeRank.EQ.0) THEN
    CALL MPI_REDUCE(RayElemPassedEnergyHO, RayElemPassedEnergyHO_Shared, MessageSize, MPI_DOUBLE_PRECISION, MPI_SUM, 0, MPI_COMM_SHARED, IERROR)
  ELSE
    CALL MPI_REDUCE(RayElemPassedEnergyHO, 0                           , MessageSize, MPI_DOUBLE_PRECISION, MPI_SUM, 0, MPI_COMM_SHARED, IERROR)
  ENDIF
  CALL BARRIER_AND_SYNC(RayElemPassedEnergyHO_Shared_Win, MPI_COMM_SHARED)

  ! Synchronize data between node leaders with all-reduce
  IF(nLeaderGroupProcs.GT.1)THEN
    IF(myComputeNodeRank.EQ.0)THEN
      CALL MPI_ALLREDUCE(MPI_IN_PLACE,RayElemPassedEnergyHO_Shared,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_LEADERS_SHARED,iError)
    END IF

    ! Synchronize data from node leaders to node workers
    CALL BARRIER_AND_SYNC(RayElemPassedEnergyHO_Shared_Win, MPI_COMM_SHARED)
  END IF

  DEALLOCATE(RayElemPassedEnergyHO)

END IF ! nProcessors.GT.1

END SUBROUTINE ExchangeRayVolInfo
#endif /*USE_MPI*/

END MODULE MOD_Photon_TrackingOutput
