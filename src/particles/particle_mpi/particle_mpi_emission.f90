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

MODULE MOD_Particle_MPI_Emission
!===================================================================================================================================
! module for particle emission
!===================================================================================================================================
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
#if USE_MPI
!===================================================================================================================================
PUBLIC :: SendEmissionParticlesToProcs
!===================================================================================================================================
CONTAINS

SUBROUTINE SendEmissionParticlesToProcs(chunkSize,DimSend,FractNbr,iInit,mySumOfMatchedParticles,particle_positions)
!----------------------------------------------------------------------------------------------------------------------------------!
! A particle's host cell in the FIBGM is found and the corresponding procs are notified.
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Eval_xyz               ,ONLY: GetPositionInRefElem
USE MOD_Particle_Localization  ,ONLY: LocateParticleInElement,SinglePointToElement
USE MOD_Particle_Mesh_Vars     ,ONLY: GEO
USE MOD_Particle_Mesh_Vars     ,ONLY: ElemInfo_Shared
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGMToProc,FIBGMProcs
!USE MOD_Mesh_Tools             ,ONLY: GetCNElemID
!USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGM_nElems, FIBGM_offsetElem, FIBGM_Element
USE MOD_Particle_Mesh_Vars     ,ONLY: FIBGM_nElems,FIBGM_nTotalElems
USE MOD_Particle_MPI_Vars      ,ONLY: PartMPI,PartMPIInsert,PartMPILocate
USE MOD_Particle_MPI_Vars      ,ONLY: EmissionSendBuf,EmissionRecvBuf
USE MOD_Particle_Vars          ,ONLY: PDM,PEM,PartState,PartPosRef,Species
USE MOD_Particle_Tracking_Vars ,ONLY: TrackingMethod
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT VARIABLES
INTEGER,INTENT(IN)            :: chunkSize
INTEGER,INTENT(IN)            :: DimSend
INTEGER,INTENT(IN)            :: FractNbr
INTEGER,INTENT(IN)            :: iInit
REAL,INTENT(IN),OPTIONAL      :: particle_positions(1:chunkSize*DimSend)
! OUTPUT VARIABLES
INTEGER,INTENT(OUT)           :: mySumOfMatchedParticles
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
! Counters
INTEGER                       :: i,iPos,iProc,iDir,ElemID,ProcID
! BGM
INTEGER                       :: ijkBGM(3,chunkSize)
INTEGER                       :: TotalNbrOfRecvParts!,iBGMElem,nBGMElems
LOGICAL                       :: InsideMyBGM(2,chunkSize)
! Temporary state arrays
REAL,ALLOCATABLE              :: chunkState(:,:)
! MPI Communication
INTEGER                       :: ALLOCSTAT,PartCommSize,ParticleIndexNbr
INTEGER                       :: InitGroup,tProc
INTEGER                       :: msg_status(1:MPI_STATUS_SIZE),messageSize
INTEGER                       :: nRecvParticles,nSendParticles
REAL,ALLOCATABLE              :: recvPartPos(:)
!===================================================================================================================================
InitGroup = Species(FractNbr)%Init(iInit)%InitCOMM

! Arrays for communication of particles not located in final element
ALLOCATE( PartMPIInsert%nPartsSend  (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPIInsert%nPartsRecv  (1,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPIInsert%SendRequest (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPIInsert%RecvRequest (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPIInsert%send_message(  0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , STAT=ALLOCSTAT)
IF (ALLOCSTAT.NE.0) &
  CALL ABORT(__STAMP__,' Cannot allocate particle emission MPI arrays! ALLOCSTAT',ALLOCSTAT)

PartMPIInsert%nPartsSend=0
PartMPIInsert%nPartsRecv=0

! Inter-CN communication
ALLOCATE( PartMPILocate%nPartsSend (2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPILocate%nPartsRecv (1,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPILocate%SendRequest(2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , PartMPILocate%RecvRequest(2,0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , EmissionRecvBuf          (  0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , EmissionSendBuf          (  0:PartMPI%InitGroup(InitGroup)%nProcs-1) &
        , STAT=ALLOCSTAT)
IF (ALLOCSTAT.NE.0) &
  CALL ABORT(__STAMP__,' Cannot allocate particle emission MPI arrays! ALLOCSTAT',ALLOCSTAT)

PartMPILocate%nPartsSend=0
PartMPILocate%nPartsRecv=0

! Arrays for communication of particles located in final element. Reuse particle_mpi infrastructure wherever possible
PartCommSize   = 0
PartCommSize   = PartCommSize + 3                              ! Emission position (physical space)
IF(TrackingMethod.EQ.REFMAPPING) PartCommSize = PartCommSize+3 ! Emission position (reference space)
!PartCommSize   = PartCommSize + 1                             ! Species-ID
PartCommSize   = PartCommSize + 1                              ! ID of element

! Temporary array to hold ElemID of located particles
ALLOCATE( chunkState(PartCommSize,chunkSize)                                                &
        , STAT=ALLOCSTAT)
IF (ALLOCSTAT.NE.0) &
  CALL ABORT(__STAMP__,' Cannot allocate particle emission MPI arrays! ALLOCSTAT',ALLOCSTAT)

chunkState = -1

!--- 1/10 Open receive buffer (located and non-located particles)
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  !--- MPI_IRECV lengths of lists of particles entering local mesh
  CALL MPI_IRECV( PartMPIInsert%nPartsRecv(:,iProc)                           &
                , 1                                                           &
                , MPI_INTEGER                                                 &
                , iProc                                                       &
                , 1011                                                        &
                , PartMPI%InitGroup(InitGroup)%COMM                           &
                , PartMPIInsert%RecvRequest(1,iProc)                          &
                , IERROR)

  ! Inter-CN communication
  CALL MPI_IRECV( PartMPILocate%nPartsRecv(:,iProc)                           &
                , 1                                                           &
                , MPI_INTEGER                                                 &
                , iProc                                                       &
                , 1111                                                        &
                , PartMPI%InitGroup(InitGroup)%COMM                           &
                , PartMPILocate%RecvRequest(1,iProc)                          &
                , IERROR)
END DO

! Identify particles that are on the node (or in the halo region of the node) or on other nodes
DO i=1,chunkSize
  ! Set BGM cell index
  ASSOCIATE( xMin   => (/GEO%xminglob  , GEO%yminglob  , GEO%zminglob/)  ,    &
             BGMMin => (/GEO%FIBGMimin , GEO%FIBGMjmin , GEO%FIBGMkmin/) ,    &
             BGMMax => (/GEO%FIBGMimax , GEO%FIBGMjmax , GEO%FIBGMkmax/) )
    DO iDir = 1, 3
      ijkBGM(iDir,i) = INT((particle_positions(DimSend*(i-1)+iDir)-xMin(iDir))/GEO%FIBGMdeltas(iDir))+1
    END DO ! iDir = 1, 3

    ! Check BGM cell index
    InsideMyBGM(:,i)=.TRUE.
    DO iDir = 1, 3
      IF(ijkBGM(iDir,i).LT.BGMMin(iDir)) THEN
        InsideMyBGM(1,i)=.FALSE.
        EXIT
      END IF
      IF(ijkBGM(iDir,i).GT.BGMMax(iDir)) THEN
        InsideMyBGM(1,i)=.FALSE.
        EXIT
      END IF
    END DO ! iDir = 1, 3
  END ASSOCIATE

  IF (InsideMyBGM(1,i)) THEN
    ASSOCIATE(iBGM => ijkBGM(1,i), &
              jBGM => ijkBGM(2,i), &
              kBGM => ijkBGM(3,i))

    !--- check if BGM cell contains elements not within the halo region
    IF (FIBGM_nElems(iBGM,jBGM,kBGM).NE.FIBGM_nTotalElems(iBGM,jBGM,kBGM)) THEN
      !--- if any elements are found, communicate particle to all procs
      InsideMyBGM(2,i) = .FALSE.
    END IF ! (FIBGM_nElems(iBGM,jBGM,kBGM).NE.FIBGM_nTotalElems(iBGM,jBGM,kBGM))
    END ASSOCIATE
  END IF ! InsideMyBGM(i)
END DO ! i = 1, chunkSize

!--- Find non-local particles for sending to other nodes
DO i = 1, chunkSize
  IF(ANY(.NOT.InsideMyBGM(:,i))) THEN
    ! Inter-CN communication
    ASSOCIATE(iBGM => ijkBGM(1,i), &
              jBGM => ijkBGM(2,i), &
              kBGM => ijkBGM(3,i))

    ! Sanity check if the emission is within the global FIBGM region
    IF (iBGM.LT.GEO%FIBGMiminglob .OR. iBGM.GT.GEO%FIBGMimaxglob .OR. &
        jBGM.LT.GEO%FIBGMjminglob .OR. jBGM.GT.GEO%FIBGMjmaxglob .OR. &
        kBGM.LT.GEO%FIBGMkminglob .OR. kBGM.GT.GEO%FIBGMkmaxglob) THEN
      CYCLE
    END IF

    !-- Find all procs associated with the background mesh cell. Then loop over all procs and count number of particles per proc for
    !-- sending
    DO iProc = FIBGMToProc(FIBGM_FIRSTPROCIND,iBGM,jBGM,kBGM)+1, &
               FIBGMToProc(FIBGM_FIRSTPROCIND,iBGM,jBGM,kBGM)+FIBGMToProc(FIBGM_NPROCS,iBGM,jBGM,kBGM)
      ProcID = FIBGMProcs(iProc)
      IF (ProcID.EQ.myRank) CYCLE

      tProc=PartMPI%InitGroup(InitGroup)%CommToGroup(ProcID)
      ! Processor is not on emission communicator
      IF(tProc.EQ.-1) CYCLE

      PartMPIInsert%nPartsSend(1,tProc) = PartMPIInsert%nPartsSend(1,tProc)+1
    END DO

    END ASSOCIATE
  END IF ! .NOT.InsideMyBGM(i)
END DO ! i = 1, chunkSize

!--- 2/10 Send number of non-located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  ! send particles
  !--- MPI_ISEND lengths of lists of particles leaving local mesh
  CALL MPI_ISEND( PartMPIInsert%nPartsSend( 1,iProc)                          &
                , 1                                                           &
                , MPI_INTEGER                                                 &
                , iProc                                                       &
                , 1011                                                        &
                , PartMPI%InitGroup(InitGroup)%COMM                           &
                , PartMPIInsert%SendRequest(1,iProc)                          &
                , IERROR)
  IF (PartMPIInsert%nPartsSend(1,iProc).GT.0) THEN
    MessageSize = DimSend*PartMPIInsert%nPartsSend(1,iProc)
    ALLOCATE( PartMPIInsert%send_message(iProc)%content(MessageSize), STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) &
      CALL ABORT(__STAMP__,'  Cannot allocate emission PartSendBuf, local ProcId, ALLOCSTAT',iProc,REAL(ALLOCSTAT))
  END IF
END DO


!--- 3/10 Send actual non-located particles
PartMPIInsert%nPartsSend(2,:)=0
DO i = 1, chunkSize
  IF(ANY(.NOT.InsideMyBGM(:,i))) THEN
    ! Inter-CN communication
    ASSOCIATE(iBGM => ijkBGM(1,i), &
          jBGM => ijkBGM(2,i), &
          kBGM => ijkBGM(3,i))

    ! Sanity check if the emission is within the global FIBGM region
    IF (iBGM.LT.GEO%FIBGMiminglob .OR. iBGM.GT.GEO%FIBGMimaxglob .OR. &
        jBGM.LT.GEO%FIBGMjminglob .OR. jBGM.GT.GEO%FIBGMjmaxglob .OR. &
        kBGM.LT.GEO%FIBGMkminglob .OR. kBGM.GT.GEO%FIBGMkmaxglob) THEN
      CYCLE
    END IF

    !-- Find all procs associated with the background mesh cell. Then loop over all procs and count number of particles per proc for
    !-- sending
    DO iProc = FIBGMToProc(FIBGM_FIRSTPROCIND,iBGM,jBGM,kBGM)+1, &
               FIBGMToProc(FIBGM_FIRSTPROCIND,iBGM,jBGM,kBGM)+FIBGMToProc(FIBGM_NPROCS,iBGM,jBGM,kBGM)
      ProcID = FIBGMProcs(iProc)
      IF (ProcID.EQ.myRank) CYCLE

      tProc=PartMPI%InitGroup(InitGroup)%CommToGroup(ProcID)
      ! Processor is not on emission communicator
      IF (tProc.EQ.-1) CYCLE

      ! Assemble message
      iPos = PartMPIInsert%nPartsSend(2,tProc) * DimSend
      PartMPIInsert%send_message(tProc)%content(iPos+1:iPos+3) = particle_positions(DimSend*(i-1)+1:DimSend*i)

      ! Counter of previous particles on proc
      PartMPIInsert%nPartsSend(2,tProc)=PartMPIInsert%nPartsSend(2,tProc) + 1
    END DO

    END ASSOCIATE
  END IF ! .NOT.InsideMyBGM(i)
END DO ! i = 1, chunkSize


!--- 4/10 Receive actual non-located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  CALL MPI_WAIT(PartMPIInsert%SendRequest(1,iProc),msg_status(:),IERROR)
  IF (IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  CALL MPI_WAIT(PartMPIInsert%RecvRequest(1,iProc),msg_status(:),IERROR)
  IF (IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
END DO

! recvPartPos holds particles from ALL procs
! Inter-CN communication
ALLOCATE(recvPartPos(1:SUM(PartMPIInsert%nPartsRecv(1,:)*DimSend)), STAT=ALLOCSTAT)
TotalNbrOfRecvParts = 0
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  IF (PartMPIInsert%nPartsRecv(1,iProc).GT.0) THEN
  !--- MPI_IRECV lengths of lists of particles entering local mesh
    CALL MPI_IRECV( recvPartPos(TotalNbrOfRecvParts*DimSend+1)                &
                  , DimSend*PartMPIInsert%nPartsRecv(1,iProc)                 &
                  , MPI_DOUBLE_PRECISION                                      &
                  , iProc                                                     &
                  , 1022                                                      &
                  , PartMPI%InitGroup(InitGroup)%COMM                         &
                  , PartMPIInsert%RecvRequest(2,iProc)                        &
                  , IERROR)
    TotalNbrOfRecvParts = TotalNbrOfRecvParts + PartMPIInsert%nPartsRecv(1,iProc)
  END IF
  !--- (non-blocking:) send messages to all procs receiving particles from myself
  IF (PartMPIInsert%nPartsSend(2,iProc).GT.0) THEN
    CALL MPI_ISEND( PartMPIInsert%send_message(iProc)%content                 &
                  , DimSend*PartMPIInsert%nPartsSend(2,iProc)                 &
                  , MPI_DOUBLE_PRECISION                                      &
                  , iProc                                                     &
                  , 1022                                                      &
                  , PartMPI%InitGroup(InitGroup)%COMM                         &
                  , PartMPIInsert%SendRequest(2,iProc)                        &
                  , IERROR)
  END IF
END DO

mySumOfMatchedParticles = 0
ParticleIndexNbr        = 1

!--- Locate local (node or halo of node) particles
DO i = 1, chunkSize
  IF(InsideMyBGM(1,i))THEN
    ! We cannot call LocateParticleInElement because we do not know the final PartID yet. Locate the position and fill PartState
    ! manually if we got a hit
    ElemID = SinglePointToElement(particle_positions(DimSend*(i-1)+1:DimSend*(i-1)+3),doHALO=.TRUE.,doEmission_opt=.TRUE.)
    ! Checked every possible cell and didn't find it. Apparently, we emitted the particle outside the domain
    IF(ElemID.EQ.-1) CYCLE

    ! Only keep the particle if it belongs on the current proc. Otherwise prepare to send it to the correct proc
    ! TODO: Implement U_Shared, so we can finish emission on this proc and send the fully initialized particle (i.e. including
    ! velocity)
    ProcID = ElemInfo_Shared(ELEM_RANK,ElemID)
    IF (ProcID.NE.myRank) THEN
      ! Particle was sent to every potential proc, so trust the other proc to find it and do not send it again
      IF (.NOT.InsideMyBGM(2,i)) CYCLE

      ! ProcID on emission communicator
      tProc=PartMPI%InitGroup(InitGroup)%CommToGroup(ProcID)
      ! Processor is not on emission communicator
      IF(tProc.EQ.-1) &
        CALL ABORT(__STAMP__,'Error in particle_mpi_emission: proc not on emission communicator')

      PartMPILocate%nPartsSend(1,tProc)= PartMPILocate%nPartsSend(1,tProc)+1

      ! Assemble temporary PartState to send the final particle position
      chunkState(1:3,i) = particle_positions(DimSend*(i-1)+1:DimSend*(i-1)+3)
      IF (TrackingMethod.EQ.REFMAPPING) THEN
        CALL GetPositionInRefElem(chunkState(1:3,i),chunkState(4:6,i),ElemID)
        chunkState(7,i) = REAL(ElemID,KIND=8)
      ELSE
        chunkState(4,i) = REAL(ElemID,KIND=8)
      END IF ! TrackingMethod.EQ.REFMAPPING
    ! Located particle on local proc.
    ELSE
      ! Get the next free position in the PDM array
      ParticleIndexNbr = PDM%nextFreePosition(mySumOfMatchedParticles + 1 + PDM%CurrentNextFreePosition)
      IF (ParticleIndexNbr.NE.0) THEN
        ! Fill the PartState manually to avoid a second localization
        PartState(1:DimSend,ParticleIndexNbr) = particle_positions(DimSend*(i-1)+1:DimSend*(i-1)+DimSend)
        PDM%ParticleInside( ParticleIndexNbr) = .TRUE.
        IF (TrackingMethod.EQ.REFMAPPING) THEN
          CALL GetPositionInRefElem(PartState(1:3,ParticleIndexNbr),PartPosRef(1:3,ParticleIndexNbr),ElemID)
        END IF ! TrackingMethod.EQ.REFMAPPING
        PEM%GlobalElemID(ParticleIndexNbr)         = ElemID
      ELSE
        CALL ABORT(__STAMP__,'ERROR in ParticleMPIEmission:ParticleIndexNbr.EQ.0 - maximum nbr of particles reached?')
      END IF
      mySumOfMatchedParticles = mySumOfMatchedParticles + 1
    END IF ! ElemID.EQ.-1
  END IF ! InsideMyBGM(i)
END DO ! i = 1, chunkSize

!---  /  Send number of located particles
! Inter-CN communication
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  ! send particles
  !--- MPI_ISEND lengths of lists of particles leaving local mesh
  CALL MPI_ISEND( PartMPILocate%nPartsSend( 1,iProc)                          &
                , 1                                                           &
                , MPI_INTEGER                                                 &
                , iProc                                                       &
                , 1111                                                        &
                , PartMPI%InitGroup(InitGroup)%COMM                           &
                , PartMPILocate%SendRequest(1,iProc)                          &
                , IERROR)
  IF (PartMPILocate%nPartsSend(1,iProc).GT.0) THEN
    MessageSize = PartMPILocate%nPartsSend(1,iProc)*PartCommSize
    ALLOCATE(EmissionSendBuf(iProc)%content(MessageSize),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) &
      CALL ABORT(__STAMP__,'  Cannot allocate emission EmissionSendBuf, local ProcId, ALLOCSTAT',iProc,REAL(ALLOCSTAT))
  END IF
END DO

!--- 5/10 Send actual located particles. PartState is filled in LocateParticleInElement
PartMPILocate%nPartsSend(2,:) = 0
DO i = 1, chunkSize
  ElemID = INT(chunkState(PartCommSize,i))
  ! Skip non-located particles
  IF(ElemID.EQ.-1) CYCLE
  ProcID = ElemInfo_Shared(ELEM_RANK,ElemID)
  IF (ProcID.NE.myRank) THEN
    ! ProcID on emission communicator
    tProc=PartMPI%InitGroup(InitGroup)%CommToGroup(ProcID)
    ! Processor is not on emission communicator
    IF(tProc.EQ.-1) CYCLE

    ! Assemble message
    iPos = PartMPILocate%nPartsSend(2,tProc) * PartCommSize
    EmissionSendBuf(tProc)%content(1+iPos:PartCommSize+iPos) = chunkState(1:PartCommSize,i)

    ! Counter of previous particles on proc
    PartMPILocate%nPartsSend(2,tProc) = PartMPILocate%nPartsSend(2,tProc) + 1
  END IF ! ProcID.NE.myRank
END DO ! i = 1, chunkSize

!--- 6/10 Receive actual non-located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  CALL MPI_WAIT(PartMPILocate%SendRequest(1,iProc),msg_status(:),IERROR)
  IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  CALL MPI_WAIT(PartMPILocate%RecvRequest(1,iProc),msg_status(:),IERROR)
  IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
END DO

DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  ! Allocate receive array and open receive buffer if expecting particles from iProc
  IF (PartMPILocate%nPartsRecv(1,iProc).GT.0) THEN
    nRecvParticles = PartMPILocate%nPartsRecv(1,iProc)
    MessageSize    = nRecvParticles * PartCommSize
    ALLOCATE(EmissionRecvBuf(iProc)%content(MessageSize),STAT=ALLOCSTAT)
    IF (ALLOCSTAT.NE.0) &
      CALL ABORT(__STAMP__,'  Cannot allocate emission EmissionRecvBuf, local ProcId, ALLOCSTAT',iProc,REAL(ALLOCSTAT))

    !--- MPI_IRECV lengths of lists of particles entering local mesh
    CALL MPI_IRECV( EmissionRecvBuf(iProc)%content                             &
                  , MessageSize                                                &
                  , MPI_DOUBLE_PRECISION                                       &
                  , iProc                                                      &
                  , 1122                                                       &
                  , PartMPI%InitGroup(InitGroup)%COMM                          &
                  , PartMPILocate%RecvRequest(2,iProc)                         &
                  , IERROR )
    IF(IERROR.NE.MPI_SUCCESS) &
      CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
  END IF
  !--- (non-blocking:) send messages to all procs receiving particles from myself
  IF (PartMPILocate%nPartsSend(2,iProc).GT.0) THEN
    nSendParticles = PartMPILocate%nPartsSend(1,iProc)
    MessageSize    = nSendParticles * PartCommSize
    CALL MPI_ISEND( EmissionSendBuf(iProc)%content                             &
                  , MessageSize                                                &
                  , MPI_DOUBLE_PRECISION                                       &
                  , iProc                                                      &
                  , 1122                                                       &
                  , PartMPI%InitGroup(InitGroup)%COMM                          &
                  , PartMPILocate%SendRequest(2,iProc)                         &
                  , IERROR )
    IF(IERROR.NE.MPI_SUCCESS) &
      CALL ABORT(__STAMP__,' MPI Communication error', IERROR)
  END IF
END DO

!--- 7/10 Finish communication of actual non-located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  IF (PartMPIInsert%nPartsSend(1,iProc).GT.0) THEN
    CALL MPI_WAIT(PartMPIInsert%SendRequest(2,iProc),msg_status(:),IERROR)
    IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  END IF
  IF (PartMPIInsert%nPartsRecv(1,iProc).GT.0) THEN
    CALL MPI_WAIT(PartMPIInsert%RecvRequest(2,iProc),msg_status(:),IERROR)
    IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  END IF
END DO

!--- 8/10 Try to locate received non-located particles
TotalNbrOfRecvParts = SUM(PartMPIInsert%nPartsRecv(1,:))
DO i = 1,TotalNbrOfRecvParts
  ! We cannot call LocateParticleInElement because we do not know the final PartID yet. Locate the position and fill PartState
  ! manually if we got a hit
  ElemID = SinglePointToElement(recvPartPos(DimSend*(i-1)+1:DimSend*(i-1)+3),doHALO=.FALSE.,doEmission_opt=.TRUE.)
  ! Checked every possible cell and didn't find it. Apparently, we emitted the particle outside the domain
  IF(ElemID.EQ.-1) CYCLE

  ! Only keep the particle if it belongs on the current proc. Trust the other procs to do their jobs and locate it if needed
  IF (ElemInfo_Shared(ELEM_RANK,ElemID).NE.myRank) CYCLE

  ! Find a free position in the PDM array
  ParticleIndexNbr = PDM%nextFreePosition(mySumOfMatchedParticles + 1 + PDM%CurrentNextFreePosition)
  IF (ParticleIndexNbr.NE.0) THEN
    ! Fill the PartState manually to avoid a second localization
    PartState(1:3,ParticleIndexNbr) = recvPartPos(DimSend*(i-1)+1:DimSend*(i-1)+3)
    PDM%ParticleInside( ParticleIndexNbr) = .TRUE.
    IF (TrackingMethod.EQ.REFMAPPING) THEN
      CALL GetPositionInRefElem(PartState(1:3,ParticleIndexNbr),PartPosRef(1:3,ParticleIndexNbr),ElemID)
    END IF ! TrackingMethod.EQ.REFMAPPING
    PEM%GlobalElemID(ParticleIndexNbr)    = ElemID
  ELSE
    CALL ABORT(__STAMP__,'ERROR in ParticleMPIEmission:ParticleIndexNbr.EQ.0 - maximum nbr of particles reached?')
  END IF
  mySumOfMatchedParticles = mySumOfMatchedParticles + 1
END DO

!--- 9/10 Finish communication of actual non-located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE

  IF (PartMPILocate%nPartsSend(1,iProc).GT.0) THEN
    CALL MPI_WAIT(PartMPILocate%SendRequest(2,iProc),msg_status(:),IERROR)
    IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  END IF
  IF (PartMPILocate%nPartsRecv(1,iProc).GT.0) THEN
    CALL MPI_WAIT(PartMPILocate%RecvRequest(2,iProc),msg_status(:),IERROR)
    IF(IERROR.NE.MPI_SUCCESS) CALL abort(__STAMP__,' MPI Communication error', IERROR)
  END IF
END DO

!--- 10/10 Write located particles
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  IF (iProc.EQ.PartMPI%InitGroup(InitGroup)%myRank) CYCLE
  IF (PartMPILocate%nPartsRecv(1,iProc).EQ.0) CYCLE

  DO i = 1,PartMPILocate%nPartsRecv(1,iProc)
    ! Find a free position in the PDM array
    ParticleIndexNbr = PDM%nextFreePosition(mySumOfMatchedParticles + 1 + PDM%CurrentNextFreePosition)
    IF (ParticleIndexNbr.NE.0) THEN
      ! Fill the PartState manually to avoid a second localization
      PartState(1:3,ParticleIndexNbr) = EmissionRecvBuf(iProc)%content(PartCommSize*(i-1)+1:PartCommSize*(i-1)+3)
      IF (TrackingMethod.EQ.REFMAPPING) THEN
        PartPosRef(1:3,ParticleIndexNbr) = EmissionRecvBuf(iProc)%content(PartCommSize*(i-1)+4:PartCommSize*(i-1)+6)
      END IF ! TrackingMethod.EQ.REFMAPPING
      PEM%GlobalElemID(ParticleIndexNbr)    = INT(EmissionRecvBuf(iProc)%content(PartCommSize*(i)),KIND=4)
      PDM%ParticleInside( ParticleIndexNbr) = .TRUE.
    ELSE
      CALL ABORT(__STAMP__,'ERROR in ParticleMPIEmission:ParticleIndexNbr.EQ.0 - maximum nbr of particles reached?')
    END IF
    mySumOfMatchedParticles = mySumOfMatchedParticles + 1
  END DO
END DO

!--- Clean up
SDEALLOCATE(recvPartPos)
SDEALLOCATE(chunkState)
DO iProc=0,PartMPI%InitGroup(InitGroup)%nProcs-1
  SDEALLOCATE(EmissionRecvBuf(iProc)%content)
  SDEALLOCATE(EmissionSendBuf(iProc)%content)
END DO
SDEALLOCATE(PartMPIInsert%nPartsSend)
SDEALLOCATE(PartMPIInsert%nPartsRecv)
SDEALLOCATE(PartMPIInsert%SendRequest)
SDEALLOCATE(PartMPIInsert%RecvRequest)
SDEALLOCATE(PartMPIInsert%send_message)

SDEALLOCATE(PartMPILocate%nPartsSend)
SDEALLOCATE(PartMPILocate%nPartsRecv)
SDEALLOCATE(PartMPILocate%SendRequest)
SDEALLOCATE(PartMPILocate%RecvRequest)
SDEALLOCATE(EmissionRecvBuf)
SDEALLOCATE(EmissionSendBuf)

END SUBROUTINE SendEmissionParticlesToProcs
#endif /*USE_MPI*/

END MODULE MOD_Particle_MPI_Emission