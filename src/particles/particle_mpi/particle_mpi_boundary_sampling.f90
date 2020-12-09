!==================================================================================================================================
! Copyright (c) 2010 - 2019 Prof. Claus-Dieter Munz and Prof. Stefanos Fasoulas
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

MODULE MOD_Particle_MPI_Boundary_Sampling
!===================================================================================================================================
! module for MPI communication of particle surface sampling
!===================================================================================================================================
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------

#if USE_MPI
INTERFACE InitSurfCommunication
  MODULE PROCEDURE InitSurfCommunication
END INTERFACE

INTERFACE ExchangeSurfData
  MODULE PROCEDURE ExchangeSurfData
END INTERFACE

INTERFACE FinalizeSurfCommunication
  MODULE PROCEDURE FinalizeSurfCommunication
END INTERFACE

PUBLIC :: InitSurfCommunication
PUBLIC :: ExchangeSurfData
PUBLIC :: FinalizeSurfCommunication
!===================================================================================================================================

CONTAINS


SUBROUTINE InitSurfCommunication()
!----------------------------------------------------------------------------------------------------------------------------------!
!
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
USE MOD_Globals
USE MOD_MPI_Shared_Vars         ,ONLY: MPI_COMM_LEADERS_SHARED,MPI_COMM_LEADERS_SURF
!USE MOD_MPI_Shared_Vars         ,ONLY: nComputeNodeProcessors
USE MOD_MPI_Shared_Vars         ,ONLY: myLeaderGroupRank,nLeaderGroupProcs
USE MOD_MPI_Shared_Vars         ,ONLY: MPIRankSharedLeader,MPIRankSurfLeader
USE MOD_MPI_Shared_Vars         ,ONLY: mySurfRank,nSurfLeaders!,nSurfCommProc
USE MOD_Particle_Boundary_Vars  ,ONLY: nComputeNodeSurfSides,nComputeNodeSurfTotalSides,offsetComputeNodeSurfSide
USE MOD_Particle_Boundary_Vars  ,ONLY: SurfOnNode,SurfSampSize,nSurfSample,CalcSurfaceImpact
USE MOD_Particle_Boundary_Vars  ,ONLY: SurfMapping
USE MOD_Particle_Boundary_Vars  ,ONLY: nSurfTotalSides
!USE MOD_Particle_Boundary_Vars  ,ONLY: GlobalSide2SurfSide
USE MOD_Particle_Boundary_Vars  ,ONLY: SurfSide2GlobalSide
USE MOD_Particle_MPI_Vars       ,ONLY: SurfSendBuf,SurfRecvBuf
USE MOD_Particle_Vars           ,ONLY: nSpecies
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT/OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                       :: msg_status(1:MPI_STATUS_SIZE)
INTEGER                       :: iProc,color
INTEGER                       :: leadersGroup,LeaderID,surfGroup
INTEGER                       :: iSide
INTEGER                       :: sendbuf,recvbuf
INTEGER                       :: nSendSurfSidesTmp(0:nLeaderGroupProcs-1)
INTEGER                       :: nRecvSurfSidesTmp(0:nLeaderGroupProcs-1)
!INTEGER                       :: nSurfSidesLeader(1:2,0:nLeaderGroupProcs-1)
INTEGER                       :: RecvRequest(0:nLeaderGroupProcs-1),SendRequest(0:nLeaderGroupProcs-1)
INTEGER                       :: SendSurfGlobalID(0:nLeaderGroupProcs-1,1:nComputeNodeSurfTotalSides)
INTEGER                       :: SampSizeAllocate
!===================================================================================================================================

nRecvSurfSidesTmp = 0

!--- Open receive buffer (number of sampling surfaces in other node's halo region)
DO iProc = 0,nLeaderGroupProcs-1
  IF (iProc.EQ.myLeaderGroupRank) CYCLE

  CALL MPI_IRECV( nRecvSurfSidesTmp(iProc)                                    &
                , 1                                                           &
                , MPI_INTEGER                                                 &
                , iProc                                                       &
                , 1211                                                        &
                , MPI_COMM_LEADERS_SHARED                                     &
                , RecvRequest(iProc)                                          &
                , IERROR)
END DO

!--- count all surf sides per other compute-node which get sampling data from current leader
nSendSurfSidesTmp = 0

DO iSide = 1,nComputeNodeSurfTotalSides
  ! count surf sides per compute node
  LeaderID = SurfSide2GlobalSide(SURF_LEADER,iSide)
  nSendSurfSidesTmp(LeaderID) = nSendSurfSidesTmp(LeaderID) + 1
  SendSurfGlobalID(LeaderID,nSendSurfSidesTmp(LeaderID)) = SurfSide2GlobalSide(SURF_SIDEID,iSide)
END DO

!--- send all other leaders the number of sampling sides coming from current node
DO iProc = 0,nLeaderGroupProcs-1
  IF (iProc.EQ.myLeaderGroupRank) CYCLE

  CALL MPI_ISEND( nSendSurfSidesTmp(iProc)                                    &
                , 1                                                           &
                , MPI_INTEGER                                                 &
                , iProc                                                       &
                , 1211                                                        &
                , MPI_COMM_LEADERS_SHARED                                     &
                , SendRequest(iProc)                                          &
                , IERROR)
END DO

!--- Finish communication
DO iProc = 0,nLeaderGroupProcs-1
  IF (iProc.EQ.myLeaderGroupRank) CYCLE

  CALL MPI_WAIT(SendRequest(iProc),MPISTATUS,IERROR)
  IF (IERROR.NE.MPI_SUCCESS) CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
  CALL MPI_WAIT(RecvRequest(iProc),MPISTATUS,IERROR)
  IF (IERROR.NE.MPI_SUCCESS) CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
END DO

!--- Split communicator from MPI_COMM_LEADER_SHARED
color = MERGE(1201,MPI_UNDEFINED,SurfOnNode)

! create new SurfMesh communicator for SurfMesh communication. Pass MPI_INFO_NULL as rank to follow the original ordering
CALL MPI_COMM_SPLIT(MPI_COMM_LEADERS_SHARED, color, MPI_INFO_NULL, MPI_COMM_LEADERS_SURF, IERROR)

! Do not participate in remainder of communication if no surf sides on node
IF (.NOT.SurfOnNode) RETURN

! Find my rank on the shared communicator, comm size and proc name
CALL MPI_COMM_RANK(MPI_COMM_LEADERS_SURF, mySurfRank  , IERROR)
CALL MPI_COMM_SIZE(MPI_COMM_LEADERS_SURF, nSurfLeaders, IERROR)

! Map global rank number into shared rank number. Returns MPI_UNDEFINED if not on the same communicator
ALLOCATE(MPIRankSharedLeader(0:nLeaderGroupProcs-1))
ALLOCATE(MPIRankSurfLeader  (0:nLeaderGroupProcs-1))
DO iProc=0,nLeaderGroupProcs-1
  MPIRankSharedLeader(iProc) = iProc
END DO

! Get handles for each group
CALL MPI_COMM_GROUP(MPI_COMM_LEADERS_SHARED,leadersGroup,IERROR)
CALL MPI_COMM_GROUP(MPI_COMM_LEADERS_SURF  ,surfGroup   ,IERROR)

! Finally translate global rank to local rank
CALL MPI_GROUP_TRANSLATE_RANKS(leadersGroup,nLeaderGroupProcs,MPIRankSharedLeader,surfGroup,MPIRankSurfLeader,IERROR)
IF (mySurfRank.EQ.0) WRITE(UNIT_stdOUt,'(A,I0,A)') ' Starting surface communication between ', nSurfLeaders, ' compute nodes...'

!!--- Count all communicated sides and build mapping for other leaders
!ALLOCATE(nSurfSidesLeader(1:2,0:nSurfLeaders-1))
!
!nSurfCommProc = 0
!DO iProc = 0,nLeaderGroupProcs-1
!  ! a leader defines itself as if it has surf sides within its local domain. However, there might be procs which neither send nor
!  ! receive sides from us. We can reduce nSurfLeaders to nSurfCommProc
!  IF (MPIRankSurfLeader(iProc).EQ.MPI_UNDEFINED) CYCLE
!!  IF ((nRecvSurfSidesTmp(iProc).EQ.0) .AND. (nSendSurfSidesTmp(iProc).EQ.0)) CYCLE
!
!  ! MPI ranks, start at 0
!  nSurfSidesLeader(1,nSurfCommProc) = nSendSurfSidesTmp(iProc)
!  nSurfSidesLeader(2,nSurfCommProc) = nRecvSurfSidesTmp(iProc)
!  nSurfCommProc = nSurfCommProc + 1
!END DO

!--- Open receive buffer (mapping from message surface ID to global side ID)
ALLOCATE(SurfMapping(0:nSurfLeaders-1))

SurfMapping(:)%nRecvSurfSides = 0
SurfMapping(:)%nSendSurfSides = 0

DO iProc = 0,nLeaderGroupProcs-1
  ! Ignore procs not on surface communicator
  IF (MPIRankSurfLeader(iProc).EQ.MPI_UNDEFINED) CYCLE
  ! Ignore myself
  IF (iProc .EQ. myLeaderGroupRank) CYCLE

  ! Save number of send and recv sides
  SurfMapping(MPIRankSurfLeader(iProc))%nRecvSurfSides = nRecvSurfSidesTmp(iProc)
  SurfMapping(MPIRankSurfLeader(iProc))%nSendSurfSides = nSendSurfSidesTmp(iProc)

  ! Only open recv buffer if we are expecting sides from this leader node
  IF (nRecvSurfSidesTmp(iProc).EQ.0) CYCLE

  ALLOCATE(SurfMapping(MPIRankSurfLeader(iProc))%RecvSurfGlobalID(1:nRecvSurfSidesTmp(iProc)))

  CALL MPI_IRECV( SurfMapping(MPIRankSurfLeader(iProc))%RecvSurfGlobalID                         &
                , nRecvSurfSidesTmp(iProc)                 &
                , MPI_INTEGER                                                 &
                , MPIRankSurfLeader(iProc)                                                      &
                , 1211                                                        &
                , MPI_COMM_LEADERS_SURF                                       &
                , RecvRequest(MPIRankSurfLeader(iProc))                                          &
                , IERROR)
END DO

DO iProc = 0,nLeaderGroupProcs-1
  ! Ignore procs not on surface communicator
  IF (MPIRankSurfLeader(iProc).EQ.MPI_UNDEFINED) CYCLE
  ! Ignore myself
  IF (iProc .EQ. myLeaderGroupRank) CYCLE

  ! Only open send buffer if we are expecting sides from this leader node
  IF (nSendSurfSidesTmp(iProc).EQ.0) CYCLE

  ALLOCATE(SurfMapping(MPIRankSurfLeader(iProc))%SendSurfGlobalID(1:nSendSurfSidesTmp(iProc)))

  SurfMapping(MPIRankSurfLeader(iProc))%SendSurfGlobalID = SendSurfGlobalID(iProc,1:nSendSurfSidesTmp(iProc))

  CALL MPI_ISEND( SurfMapping(MPIRankSurfLeader(iProc))%SendSurfGlobalID                         &
                , nSendSurfSidesTmp(iProc)                 &
                , MPI_INTEGER                                                 &
                , MPIRankSurfLeader(iProc) &
                , 1211                                                        &
                , MPI_COMM_LEADERS_SURF                                       &
                , SendRequest(MPIRankSurfLeader(iProc))                                          &
                , IERROR)
END DO

!--- Finish communication
DO iProc = 0,nLeaderGroupProcs-1
  ! Ignore procs not on surface communicator
  IF (MPIRankSurfLeader(iProc).EQ.MPI_UNDEFINED) CYCLE
  ! Ignore myself
  IF (iProc .EQ. myLeaderGroupRank) CYCLE

  IF (nSendSurfSidesTmp(iProc).NE.0) THEN
    CALL MPI_WAIT(SendRequest(MPIRankSurfLeader(iProc)),msg_status(:),IERROR)
    IF (IERROR.NE.MPI_SUCCESS) CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
  END IF

  IF (nRecvSurfSidesTmp(iProc).NE.0) THEN
    CALL MPI_WAIT(RecvRequest(MPIRankSurfLeader(iProc)),msg_status(:),IERROR)
    IF (IERROR.NE.MPI_SUCCESS) CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
  END IF
END DO

!--- Allocate send and recv buffer for each surf leader
ALLOCATE(SurfSendBuf(0:nSurfLeaders-1))
ALLOCATE(SurfRecvBuf(0:nSurfLeaders-1))

DO iProc = 0,nSurfLeaders-1
  ! Get message size
  SampSizeAllocate = SurfSampSize
  ! Sampling of impact energy for each species (trans, rot, vib), impact vector (x,y,z), angle and number
  IF(CalcSurfaceImpact) SampSizeAllocate = SampSizeAllocate + 8*nSpecies

  ! Only allocate send buffer if we are expecting sides from this leader node
  IF (SurfMapping(iProc)%nSendSurfSides.GT.0) THEN
    ALLOCATE(SurfSendBuf(iProc)%content(SampSizeAllocate*(nSurfSample**2)*SurfMapping(iProc)%nSendSurfSides))
    SurfSendBuf(iProc)%content = 0.
  END IF

  ! Only allocate recv buffer if we are expecting sides from this leader node
  IF (SurfMapping(iProc)%nRecvSurfSides.GT.0) THEN
    ALLOCATE(SurfRecvBuf(iProc)%content(SampSizeAllocate*(nSurfSample**2)*SurfMapping(iProc)%nRecvSurfSides))
    SurfRecvBuf(iProc)%content = 0.
  END IF
END DO ! iProc


!--- Save number of total surf sides
!IF (surfOnNode) THEN
  IF (nSurfLeaders.EQ.1) THEN
    offsetComputeNodeSurfSide = 0
    nSurfTotalSides           = nComputeNodeSurfSides
  ELSE
    sendbuf = nComputeNodeSurfSides
    recvbuf = 0
    CALL MPI_EXSCAN(sendbuf,recvbuf,1,MPI_INTEGER,MPI_SUM,MPI_COMM_LEADERS_SURF,iError)
    offsetComputeNodeSurfSide = recvbuf
    ! last proc knows CN total number of BC elems
    sendbuf = offsetComputeNodeSurfSide + nComputeNodeSurfSides
    CALL MPI_BCAST(sendbuf,1,MPI_INTEGER,nSurfLeaders-1,MPI_COMM_LEADERS_SURF,iError)
    nSurfTotalSides = sendbuf
  END IF
!END IF


END SUBROUTINE InitSurfCommunication


SUBROUTINE ExchangeSurfData()
!===================================================================================================================================
! exchange the surface data
!> 1) collect the information on the local compute-node
!> 2) compute-node leaders with sampling sides in their halo region and the original node communicate the sampling information
!> 3) compute-node leaders ensure synchronization of shared arrays on their node
!!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_MPI_Shared_Vars         ,ONLY: MPI_COMM_SHARED,MPI_COMM_LEADERS_SURF
USE MOD_MPI_Shared_Vars         ,ONLY: nSurfLeaders,myComputeNodeRank,mySurfRank
USE MOD_Particle_Boundary_Vars  ,ONLY: SurfOnNode
USE MOD_Particle_Boundary_Vars  ,ONLY: SurfSampSize,SurfSampSizeReactive,nSurfSample
USE MOD_Particle_Boundary_Vars  ,ONLY: nComputeNodeSurfTotalSides
USE MOD_Particle_Boundary_Vars  ,ONLY: GlobalSide2SurfSide
USE MOD_Particle_Boundary_Vars  ,ONLY: SurfMapping,PartBound,CalcSurfaceImpact
USE MOD_Particle_Boundary_Vars  ,ONLY: SampWallState,SampWallState_Shared,SampWallState_Shared_Win
USE MOD_Particle_Boundary_Vars  ,ONLY: SampWallPumpCapacity,SampWallPumpCapacity_Shared,SampWallPumpCapacity_Shared_Win
USE MOD_Particle_Boundary_Vars  ,ONLY: SampWallImpactEnergy,SampWallImpactEnergy_Shared,SampWallImpactEnergy_Shared_Win
USE MOD_Particle_Boundary_Vars  ,ONLY: SampWallImpactVector,SampWallImpactVector_Shared,SampWallImpactVector_Shared_Win
USE MOD_Particle_Boundary_Vars  ,ONLY: SampWallImpactAngle ,SampWallImpactAngle_Shared ,SampWallImpactAngle_Shared_Win
USE MOD_Particle_Boundary_Vars  ,ONLY: SampWallImpactNumber,SampWallImpactNumber_Shared,SampWallImpactNumber_Shared_Win
USE MOD_Particle_MPI_Vars       ,ONLY: SurfSendBuf,SurfRecvBuf
USE MOD_Particle_Vars           ,ONLY: nSpecies
USE MOD_SurfaceModel_Vars       ,ONLY: nPorousBC
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                         :: iProc,SideID
INTEGER                         :: iPos,p,q
INTEGER                         :: MessageSize,iSurfSide,SurfSideID
INTEGER                         :: nValues,nReactiveValues
INTEGER                         :: RecvRequest(0:nSurfLeaders-1),SendRequest(0:nSurfLeaders-1)
!INTEGER                         :: iPos,p,q,iProc,iReact
!INTEGER                         :: recv_status_list(1:MPI_STATUS_SIZE,1:SurfCOMM%nMPINeighbors)
!===================================================================================================================================
! nodes without sampling surfaces do not take part in this routine
IF (.NOT.SurfOnNode) RETURN

! collect the information from the proc-local shadow arrays in the compute-node shared array
MessageSize = SurfSampSize*nSurfSample*nSurfSample*nComputeNodeSurfTotalSides
IF (myComputeNodeRank.EQ.0) THEN
  CALL MPI_REDUCE(SampWallState,SampWallState_Shared,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
ELSE
  CALL MPI_REDUCE(SampWallState,0                   ,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
ENDIF
!
IF(nPorousBC.GT.0) THEN
  MessageSize = nComputeNodeSurfTotalSides
  IF (myComputeNodeRank.EQ.0) THEN
    CALL MPI_REDUCE(SampWallPumpCapacity,SampWallPumpCapacity_Shared,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
  ELSE
    CALL MPI_REDUCE(SampWallPumpCapacity,0                          ,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
  END IF
END IF
! Sampling of impact energy for each species (trans, rot, vib), impact vector (x,y,z) and angle
IF (CalcSurfaceImpact) THEN
  IF (myComputeNodeRank.EQ.0) THEN
    MessageSize = nSpecies*3*nSurfSample*nSurfSample*nComputeNodeSurfTotalSides
    CALL MPI_REDUCE(SampWallImpactEnergy,SampWallImpactEnergy_Shared,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
    CALL MPI_REDUCE(SampWallImpactVector,SampWallImpactVector_Shared,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
    MessageSize = nSpecies*nSurfSample*nSurfSample*nComputeNodeSurfTotalSides
    CALL MPI_REDUCE(SampWallImpactAngle ,SampWallImpactAngle_Shared ,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
    CALL MPI_REDUCE(SampWallImpactNumber,SampWallImpactNumber_Shared,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
  ELSE
    MessageSize = nSpecies*3*nSurfSample*nSurfSample*nComputeNodeSurfTotalSides
    CALL MPI_REDUCE(SampWallImpactEnergy,0                          ,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
    CALL MPI_REDUCE(SampWallImpactVector,0                          ,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
    MessageSize = nSpecies*nSurfSample*nSurfSample*nComputeNodeSurfTotalSides
    CALL MPI_REDUCE(SampWallImpactAngle ,0                          ,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
    CALL MPI_REDUCE(SampWallImpactNumber,0                          ,MessageSize,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_SHARED,IERROR)
  END IF
END IF

CALL MPI_WIN_SYNC(SampWallState_Shared_Win       ,IERROR)
IF(nPorousBC.GT.0) THEN
  CALL MPI_WIN_SYNC(SampWallPumpCapacity_Shared_Win,IERROR)
END IF
IF (CalcSurfaceImpact) THEN
  CALL MPI_WIN_SYNC(SampWallImpactEnergy_Shared_Win,IERROR)
  CALL MPI_WIN_SYNC(SampWallImpactVector_Shared_Win,IERROR)
  CALL MPI_WIN_SYNC(SampWallImpactAngle_Shared_Win ,IERROR)
  CALL MPI_WIN_SYNC(SampWallImpactNumber_Shared_Win,IERROR)
END IF
CALL MPI_BARRIER(MPI_COMM_SHARED,IERROR)

! prepare buffers for surf leader communication
IF (myComputeNodeRank.EQ.0) THEN
  nValues = SurfSampSize*nSurfSample**2
  ! additional array entries for Coverage, Accomodation and recombination coefficient
  IF(ANY(PartBound%Reactive)) THEN
    nReactiveValues = SurfSampSizeReactive*(nSurfSample)**2
    nValues         = nValues+nReactiveValues
  END IF
  ! Sampling of impact energy for each species (trans, rot, vib), impact vector (x,y,z), angle and number: Add 8*nSpecies to the
  ! buffer length
  IF(CalcSurfaceImpact) nValues=nValues+8*nSpecies
  IF(nPorousBC.GT.0) nValues = nValues + 1

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
          SurfSendBuf(iProc)%content(iPos+1:iPos+SurfSampSize) = SampWallState_Shared(:,p,q,SurfSideID)
          iPos = iPos + SurfSampSize
          ! Sampling of impact energy for each species (trans, rot, vib), impact vector (x,y,z), angle and number of impacts
          IF (CalcSurfaceImpact) THEN
            ! Add average impact energy for each species (trans, rot, vib)
            SurfSendBuf(iProc)%content(iPos+1:iPos+nSpecies) = SampWallImpactEnergy_Shared(:,1,p,q,SurfSideID)
            iPos = iPos + nSpecies
            SurfSendBuf(iProc)%content(iPos+1:iPos+nSpecies) = SampWallImpactEnergy_Shared(:,2,p,q,SurfSideID)
            iPos=iPos + nSpecies
            SurfSendBuf(iProc)%content(iPos+1:iPos+nSpecies) = SampWallImpactEnergy_Shared(:,3,p,q,SurfSideID)
            iPos=iPos + nSpecies

            ! Add average impact vector (x,y,z) for each species
            SurfSendBuf(iProc)%content(iPos+1:iPos+nSpecies) = SampWallImpactVector_Shared(:,1,p,q,SurfSideID)
            iPos = iPos + nSpecies
            SurfSendBuf(iProc)%content(iPos+1:iPos+nSpecies) = SampWallImpactVector_Shared(:,2,p,q,SurfSideID)
            iPos = iPos + nSpecies
            SurfSendBuf(iProc)%content(iPos+1:iPos+nSpecies) = SampWallImpactVector_Shared(:,3,p,q,SurfSideID)
            iPos = iPos + nSpecies

            ! Add average impact angle for each species
            SurfSendBuf(iProc)%content(iPos+1:iPos+nSpecies) = SampWallImpactAngle_Shared(:,p,q,SurfSideID)
            iPos = iPos + nSpecies

            ! Add number of particle impacts
            SurfSendBuf(iProc)%content(iPos+1:iPos+nSpecies) = SampWallImpactNumber_Shared(:,p,q,SurfSideID)
            iPos = iPos + nSpecies
          END IF ! CalcSurfaceImpact
        END DO ! p=0,nSurfSample
      END DO ! q=0,nSurfSample
      IF(nPorousBC.GT.0) THEN
        SurfSendBuf(iProc)%content(iPos+1:iPos+1) = SampWallPumpCapacity_Shared(SurfSideID)
        iPos = iPos + 1
      END IF

      SampWallState_Shared(:,:,:,SurfSideID)=0.
      ! Sampling of impact energy for each species (trans, rot, vib), impact vector (x,y,z), angle and number of impacts
      IF (CalcSurfaceImpact) THEN
        SampWallImpactEnergy_Shared(:,:,:,:,SurfSideID) = 0.
        SampWallImpactVector_Shared(:,:,:,:,SurfSideID) = 0.
        SampWallImpactAngle_Shared (:,:,:,SurfSideID)   = 0.
        SampWallImpactNumber_Shared(:,:,:,SurfSideID)   = 0.
      END IF ! CalcSurfaceImpact
      IF(nPorousBC.GT.0) THEN
        SampWallPumpCapacity_Shared(SurfSideID) = 0.
      END IF
    END DO ! iSurfSide=1,nSurfExchange%nSidesSend(iProc)
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

      DO q=1,nSurfSample
        DO p=1,nSurfSample
          SampWallState_Shared(:,p,q,SurfSideID) = SampWallState_Shared(:,p,q,SurfSideID) &
                                                 + SurfRecvBuf(iProc)%content(iPos+1:iPos+SurfSampSize)
          iPos = iPos + SurfSampSize
          ! Sampling of impact energy for each species (trans, rot, vib), impact vector (x,y,z) and angle
          IF(CalcSurfaceImpact)THEN
            ! Add average impact energy for each species (trans, rot, vib)
            SampWallImpactEnergy_Shared(:,1,p,q,SurfSideID) = SampWallImpactEnergy_Shared(:,1,p,q,SurfSideID) &
                                                            + SurfRecvBuf(iProc)%content(iPos+1:iPos+nSpecies)
            iPos = iPos + nSpecies
            SampWallImpactEnergy_Shared(:,2,p,q,SurfSideID) = SampWallImpactEnergy_Shared(:,2,p,q,SurfSideID) &
                                                            + SurfRecvBuf(iProc)%content(iPos+1:iPos+nSpecies)
            iPos = iPos + nSpecies
            SampWallImpactEnergy_Shared(:,3,p,q,SurfSideID) = SampWallImpactEnergy_Shared(:,3,p,q,SurfSideID) &
                                                            + SurfRecvBuf(iProc)%content(iPos+1:iPos+nSpecies)
            iPos = iPos + nSpecies
            ! Add average impact vector (x,y,z) for each species
            SampWallImpactVector_Shared(:,1,p,q,SurfSideID) = SampWallImpactVector_Shared(:,1,p,q,SurfSideID) &
                                                            + SurfRecvBuf(iProc)%content(iPos+1:iPos+nSpecies)
            iPos = iPos + nSpecies
            SampWallImpactVector_Shared(:,2,p,q,SurfSideID) = SampWallImpactVector_Shared(:,2,p,q,SurfSideID) &
                                                            + SurfRecvBuf(iProc)%content(iPos+1:iPos+nSpecies)
            iPos = iPos + nSpecies
            SampWallImpactVector_Shared(:,3,p,q,SurfSideID) = SampWallImpactVector_Shared(:,3,p,q,SurfSideID) &
                                                            + SurfRecvBuf(iProc)%content(iPos+1:iPos+nSpecies)
            iPos = iPos + nSpecies
            ! Add average impact angle for each species
            SampWallImpactAngle_Shared(:,p,q,SurfSideID)    = SampWallImpactAngle_Shared(:,p,q,SurfSideID)    &
                                                            + SurfRecvBuf(iProc)%content(iPos+1:iPos+nSpecies)
            iPos = iPos + nSpecies
            ! Add number of particle impacts
            SampWallImpactNumber_Shared(:,p,q,SurfSideID)   = SampWallImpactNumber_Shared(:,p,q,SurfSideID)   &
                                                            + SurfRecvBuf(iProc)%content(iPos+1:iPos+nSpecies)
            iPos = iPos + nSpecies
          END IF ! CalcSurfaceImpact
        END DO ! p = 0,nSurfSample
      END DO ! q = 0,nSurfSample
      IF(nPorousBC.GT.0) THEN
        SampWallPumpCapacity_Shared(SurfSideID) = SurfRecvBuf(iProc)%content(iPos+1)
        iPos = iPos + 1
      END IF
    END DO ! iSurfSide = 1,SurfMapping(iProc)%nRecvSurfSides
     ! Nullify buffer
    SurfRecvBuf(iProc)%content = 0.
  END DO ! iProc
END IF

! ensure synchronization on compute node
CALL MPI_WIN_SYNC(SampWallState_Shared_Win       ,IERROR)
IF(nPorousBC.GT.0) THEN
  CALL MPI_WIN_SYNC(SampWallPumpCapacity_Shared_Win,IERROR)
END IF
IF (CalcSurfaceImpact) THEN
  CALL MPI_WIN_SYNC(SampWallImpactEnergy_Shared_Win,IERROR)
  CALL MPI_WIN_SYNC(SampWallImpactVector_Shared_Win,IERROR)
  CALL MPI_WIN_SYNC(SampWallImpactAngle_Shared_Win ,IERROR)
  CALL MPI_WIN_SYNC(SampWallImpactNumber_Shared_Win,IERROR)
END IF
CALL MPI_BARRIER(MPI_COMM_SHARED,IERROR)

END SUBROUTINE ExchangeSurfData


SUBROUTINE FinalizeSurfCommunication()
!----------------------------------------------------------------------------------------------------------------------------------!
! Deallocated arrays used for sampling surface communication
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES
USE MOD_Particle_Boundary_Vars  ,ONLY: SurfOnNode
USE MOD_Particle_Boundary_Vars  ,ONLY: SurfMapping
USE MOD_Particle_MPI_Vars       ,ONLY: SurfSendBuf,SurfRecvBuf
USE MOD_MPI_Shared_Vars         ,ONLY: myComputeNodeRank,mySurfRank
USE MOD_MPI_Shared_Vars         ,ONLY: MPIRankSharedLeader,MPIRankSurfLeader
USE MOD_MPI_Shared_Vars         ,ONLY: nSurfLeaders
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------!
! INPUT/OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                       :: iProc
!===================================================================================================================================

IF (myComputeNodeRank.NE.0) RETURN

! nodes without sampling surfaces do not take part in this routine
IF (.NOT.SurfOnNode) RETURN

SDEALLOCATE(MPIRankSharedLeader)
SDEALLOCATE(MPIRankSurfLeader)

DO iProc = 0,nSurfLeaders-1
  ! Ignore myself
  IF (iProc .EQ. mySurfRank) CYCLE

  IF (SurfMapping(iProc)%nRecvSurfSides.NE.0) THEN
    SDEALLOCATE(SurfMapping(iProc)%RecvSurfGlobalID)
    SDEALLOCATE(SurfMapping(iProc)%RecvPorousGlobalID)
    SDEALLOCATE(SurfRecvBuf(iProc)%content)
  END IF

  IF (SurfMapping(iProc)%nSendSurfSides.NE.0) THEN
    SDEALLOCATE(SurfMapping(iProc)%SendSurfGlobalID)
    SDEALLOCATE(SurfMapping(iProc)%SendPorousGlobalID)
    SDEALLOCATE(SurfSendBuf(iProc)%content)
  END IF
END DO
SDEALLOCATE(SurfMapping)
SDEALLOCATE(SurfSendBuf)
SDEALLOCATE(SurfRecvBuf)

END SUBROUTINE FinalizeSurfCommunication
#endif /*USE_MPI*/

END MODULE MOD_Particle_MPI_Boundary_Sampling
