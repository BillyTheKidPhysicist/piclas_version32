#include "boltzplatz.h"


MODULE MOD_PoyntingInt
!===================================================================================================================================
! Contains the Poyntinc Vector Integral part for the power analysis of the field vector
!===================================================================================================================================
USE MOD_Globals, ONLY:UNIT_stdout
USE MOD_PreProc
!===================================================================================================================================
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
!----------------------------------------------------------------------------------------------------------------------------------

INTERFACE GetPoyntingIntPlane
  MODULE PROCEDURE GetPoyntingIntPlane
END INTERFACE

INTERFACE FinalizePoyntingInt
  MODULE PROCEDURE FinalizePoyntingInt
END INTERFACE

INTERFACE CalcPoyntingIntegral
  MODULE PROCEDURE CalcPoyntingIntegral
END INTERFACE

PUBLIC:: GetPoyntingIntPlane,FinalizePoyntingInt, CalcPoyntingIntegral
!===================================================================================================================================

CONTAINS

SUBROUTINE CalcPoyntingIntegral(t)
!===================================================================================================================================
! Calculation of Poynting Integral with its own Prolong to face // check if Gauss-Labatto or Gaus Points is used is missing ... ups
!===================================================================================================================================
! MODULES
USE MOD_Mesh_Vars             ,ONLY:nPoyntingIntSides, isPoyntingIntSide,nElems, SurfElem, NormVec,whichPoyntingPlane
USE MOD_Mesh_Vars             ,ONLY:ElemToSide,SideToElem,Face_xGP
USE MOD_Analyze_Vars          ,ONLY:nPoyntingIntPlanes,PoyntingIntPlaneFactor,wGPSurf, S!, STEM
USE MOD_Interpolation_Vars    ,ONLY:L_Minus,L_Plus
USE MOD_DG_Vars               ,ONLY:U
USE MOD_Equation_Vars         ,ONLY:mu0,eps0,smu0
#ifdef MPI
  USE MOD_Globals
  USE MOD_part_MPI_Vars       ,ONLY:PMPIVAR
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(INOUT):: t
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER          :: iElem, SideID,ilocSide,iPoyntingSide
INTEGER          :: p,q,l
REAL             :: Uface(PP_nVar,0:PP_N,0:PP_N)
REAL             :: SIP(0:PP_N,0:PP_N)
REAL             :: Sabs(nPoyntingIntPlanes), STEMabs(nPoyntingIntPlanes)
#ifdef MPI
REAL             :: SumSabs(nPoyntingIntPlanes)
#endif
!REAL             :: sresvac
!===================================================================================================================================

! TEM coefficient
!sresvac = 1./sqrt(mu0/eps0)

S    = 0.
!STEM = 0.
Sabs = 0.
STEMabs = 0.

iPoyntingSide = 0 ! only if all poynting vectors are desirred
DO iELEM = 1, nElems
  Do ilocSide = 1, 6
    IF(ElemToSide(E2S_FLIP,ilocSide,iElem)==0)THEN ! only master sides
      SideID=ElemToSide(E2S_SIDE_ID,ilocSide,iElem)
      IF(isPoyntingIntSide(SideID)) THEN ! only poynting sides
#if (PP_NodeType==1) /* for Gauss-points*/
        SELECT CASE(ilocSide)
        CASE(XI_MINUS)
          DO q=0,PP_N
            DO p=0,PP_N
              Uface(:,q,p)=U(:,0,p,q,iElem)*L_Minus(0)
              DO l=1,PP_N
                ! switch to right hand system
                Uface(:,q,p)=Uface(:,q,p)+U(:,l,p,q,iElem)*L_Minus(l)
              END DO ! l
            END DO ! p
          END DO ! q
        CASE(ETA_MINUS)
          DO q=0,PP_N
            DO p=0,PP_N
                      Uface(:,p,q)=U(:,p,0,q,iElem)*L_Minus(0)
                      DO l=1,PP_N
                Uface(:,p,q)=Uface(:,p,q)+U(:,p,l,q,iElem)*L_Minus(l)
              END DO ! l
            END DO ! p
          END DO ! q
        CASE(ZETA_MINUS)
          DO q=0,PP_N
            DO p=0,PP_N
              Uface(:,q,p)=U(:,p,q,0,iElem)*L_Minus(0)
              DO l=1,PP_N
                ! switch to right hand system
                Uface(:,q,p)=Uface(:,q,p)+U(:,p,q,l,iElem)*L_Minus(l)
              END DO ! l
            END DO ! p
          END DO ! q
        CASE(XI_PLUS)
          DO q=0,PP_N
            DO p=0,PP_N
              Uface(:,p,q)=U(:,0,p,q,iElem)*L_Plus(0)
              DO l=1,PP_N
                Uface(:,p,q)=Uface(:,p,q)+U(:,l,p,q,iElem)*L_Plus(l)
              END DO ! l
            END DO ! p
          END DO ! q
        CASE(ETA_PLUS)
          DO q=0,PP_N
            DO p=0,PP_N
              Uface(:,PP_N-p,q)=U(:,p,0,q,iElem)*L_Plus(0)
              DO l=1,PP_N
                ! switch to right hand system
                Uface(:,PP_N-p,q)=Uface(:,PP_N-p,q)+U(:,p,l,q,iElem)*L_Plus(l)
              END DO ! l
            END DO ! p
          END DO ! q
        CASE(ZETA_PLUS)
          DO q=0,PP_N
            DO p=0,PP_N
              Uface(:,p,q)=U(:,p,q,0,iElem)*L_Plus(0)
              DO l=1,PP_N
                Uface(:,p,q)=Uface(:,p,q)+U(:,p,q,l,iElem)*L_Plus(l)
              END DO ! l
            END DO ! p
          END DO ! q
        END SELECT
#else /* for Gauss-Lobatto-points*/
        SELECT CASE(ilocSide)
        CASE(XI_MINUS)
          DO q=0,PP_N
            DO p=0,PP_N
              Uface(:,q,p)=U(:,0,p,q,iElem)
            END DO ! p
          END DO ! q
        CASE(ETA_MINUS)
          Uface(:,:,:)=U(:,:,0,:,iElem)
        CASE(ZETA_MINUS)
          DO q=0,PP_N
            DO p=0,PP_N
              Uface(:,q,p)=U(:,p,q,0,iElem)
            END DO ! p
          END DO ! q
        CASE(XI_PLUS)
          Uface(:,:,:)=U(:,PP_N,:,:,iElem)
        CASE(ETA_PLUS)
          DO q=0,PP_N
            DO p=0,PP_N
              Uface(:,PP_N-p,q)=U(:,p,PP_N,q,iElem)
            END DO ! p
          END DO ! q
        CASE(ZETA_PLUS)
          DO q=0,PP_N
            DO p=0,PP_N
              Uface(:,p,q)=U(:,p,q,PP_N,iElem)
            END DO ! p
          END DO ! q
        END SELECT
#endif
        ! calculate poynting vector
        iPoyntingSide = iPoyntingSide + 1
        CALL PoyntingVector(Uface(:,:,:),S(:,:,:,iPoyntingSide))
        IF ( NormVec(3,0,0,SideID) .GT. 0 ) THEN
          SIP(:,:) = S(1,:,:,iPoyntingSide) * NormVec(1,:,:,SideID) &
                   + S(2,:,:,iPoyntingSide) * NormVec(2,:,:,SideID) &
                   + S(3,:,:,iPoyntingSide) * NormVec(3,:,:,SideID)
        ELSE ! NormVec(3,:,:,iPoyningSide) < 0
          SIP(:,:) =-S(1,:,:,iPoyntingSide) * NormVec(1,:,:,SideID) &
                   - S(2,:,:,iPoyntingSide) * NormVec(2,:,:,SideID) &
                   - S(3,:,:,iPoyntingSide) * NormVec(3,:,:,SideID)
        END IF ! NormVec(3,:,:,iPoyntingSide)
        ! multiplied by surface element and  Gaus Points
        SIP(:,:) = SIP(:,:) * SurfElem(:,:,SideID) * wGPSurf(:,:)
        ! total flux through each plane
        Sabs(whichPoyntingPlane(SideID)) = Sabs(whichPoyntingPlane(SideID)) + smu0* SUM(SIP(:,:))
      END IF ! isPoyntingSide = .TRUE.
    END IF ! flip =0
  END DO ! iSides
END DO ! iElems

#ifdef MPI
  CALL MPI_ALLREDUCE(Sabs(:) , sumSabs(:) , nPoyntingIntPlanes , MPI_DOUBLE_PRECISION, MPI_SUM, PMPIVAR%COMM, IERROR)
  Sabs(:) = sumSabs(:)
#endif /* MPI */

! output callling
CALL OutputPoyntingInt(t,Sabs(:)) 

END SUBROUTINE CalcPoyntingIntegral

SUBROUTINE PoyntingVector(Uface_in,Sloc)
!===================================================================================================================================
! Calculate the Poynting Vector on a certain face
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)       :: Uface_in(PP_nVar,0:PP_N,0:PP_N)
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)      :: Sloc(1:3,0:PP_N,0:PP_N)
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: p,q
!===================================================================================================================================

! calculate the poynting vector at each node, additionally the abs of the poynting vector only based on E
DO p = 0,PP_N
  DO q = 0,PP_N
    Sloc(1,p,q)  =  Uface_in(2,p,q)*Uface_in(6,p,q) - Uface_in(3,p,q)*Uface_in(5,p,q) 
    Sloc(2,p,q)  = -Uface_in(1,p,q)*Uface_in(6,p,q) + Uface_in(3,p,q)*Uface_in(4,p,q) 
    Sloc(3,p,q)  =  Uface_in(1,p,q)*Uface_in(5,p,q) - Uface_in(2,p,q)*Uface_in(4,p,q) 
  END DO ! q - PP_N
END DO  ! p - PP_N

END SUBROUTINE PoyntingVector


SUBROUTINE OutputPoyntingInt(t,Sabs)
!===================================================================================================================================
! Output of PoyntingVector Integral to *csv vile
!===================================================================================================================================
! MODULES
USE MOD_Analyze_Vars          ,ONLY:nPoyntingIntPlanes,PosPoyntingInt
USE MOD_Restart_Vars          ,ONLY:DoRestart
#ifdef MPI
  USE MOD_Globals
  USE MOD_part_MPI_Vars       ,ONLY:PMPIVAR
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)     :: t, Sabs(nPoyntingIntPlanes)
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER             :: unit_index_PI, iPlane
LOGICAL             :: isRestart, isOpen,FileExists
CHARACTER(LEN=64)   :: filename_PI
!===================================================================================================================================
isRestart=.FALSE.
IF (DoRestart) THEN
  isRestart=.TRUE.
END IF

filename_PI  = 'Power.csv'
unit_index_PI=273

#ifdef MPI
 IF (PMPIVAR%iProc .EQ. 0) THEN
#endif    /* MPI */

INQUIRE(UNIT   = unit_index_PI , OPENED = isOpen)
IF (.NOT.isOpen) THEN
  INQUIRE(file=TRIM(filename_PI),EXIST=FileExists)
  IF (isRestart .and. FileExists) THEN
    OPEN(unit_index_PI,file=TRIM(filename_PI),position="APPEND",status="OLD")
  ELSE
    OPEN(unit_index_PI,file=TRIM(filename_PI))
    ! --- insert header
    WRITE(unit_index_PI,'(A6,A5)',ADVANCE='NO') 'TIME', ' '
    DO iPlane = 1, nPoyntingIntPlanes
      WRITE(unit_index_PI,'(A1)',ADVANCE='NO') ','
      WRITE(unit_index_PI,'(A14,F5.3)',ADVANCE='NO') 'Plane-Pos-', PosPoyntingInt(iPlane)
    END DO              
    WRITE(unit_index_PI,'(A1)') ''
  END IF
END IF
! write data to file
WRITE(unit_index_PI,'(e25.14)',ADVANCE='NO') t
DO iPlane = 1, nPoyntingIntPlanes
  WRITE(unit_index_PI,'(A1)',ADVANCE='NO') ','
  WRITE(unit_index_PI,'(e25.14)',ADVANCE='NO') Sabs(iPlane)
END DO
WRITE(unit_index_PI,'(A1)') ''

#ifdef MPI
 END IF
#endif    /* MPI */

END SUBROUTINE OutputPoyntingInt

SUBROUTINE GetPoyntingIntPlane()
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Mesh_Vars         ,ONLY:nPoyntingIntSides, isPoyntingIntSide,nSides,nElems,Face_xGP,whichPoyntingPlane,BCFace_xGP
USE MOD_Mesh_Vars         ,ONLY:ElemToSide,normvec,SideToElem
USE MOD_Analyze_Vars      ,ONLY:PoyntingIntCoordErr,nPoyntingIntPlanes,PosPoyntingInt,PoyntingIntPlaneFactor , S, STEM
USE MOD_ReadInTools       ,ONLY:GETINT,GETREAL
#ifdef MPI
  USE MOD_Globals
  USE MOD_part_MPI_Vars   ,ONLY:PMPIVAR
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER             :: iElem, iSide, iPlane, SideID, iLocsideID,iLocSide
INTEGER,ALLOCATABLE :: nFaces(:)
REAL                :: diff
REAL                :: testvec ! only in z
INTEGER             :: p,q
CHARACTER(LEN=32)   :: index_plane
#ifdef MPI
  INTEGER,ALLOCATABLE :: sumFaces(:)
  INTEGER             :: sumAllfaces
#endif /* MPI */
!===================================================================================================================================

SWRITE(UNIT_stdOut,'(A)') ' GET PLANES TO CALCULATE POYNTING VECTOR INTEGRAL ...'

! first stuff
nPoyntingIntSides=0 
ALLOCATE(isPoyntingIntSide(1:nSides))
isPoyntingIntSide = .FALSE.

! know get number of planes and coordinates
nPoyntingIntPlanes = GETINT('PoyntingVecInt-Planes','0')
ALLOCATE(PosPoyntingInt(nPoyntingIntPlanes))
ALLOCATE(PoyntingIntPlaneFactor(nPoyntingIntPlanes))
ALLOCATE(whichPoyntingPlane(nSides))
ALLOCATE(nFaces(nPoyntingIntPlanes))
whichPoyntingPlane = -1
nFaces(:) = 0

DO iPlane=1,nPoyntingIntPlanes
 WRITE(UNIT=index_plane,FMT='(I2.2)') iPlane 
 PosPoyntingInt(iPlane)= GETREAL('Plane-'//TRIM(index_plane)//'-z-coord','0.')
 PoyntingIntPlaneFactor= GETREAL('Plane-'//TRIM(index_plane)//'-factor','1.')
END DO
PoyntingIntCoordErr=GETREAL('Plane-Tolerance','1E-5')

! loop over all planes
DO iPlane = 1, nPoyntingIntPlanes
  ! loop over all elements
  DO iElem=1,nElems
    ! loop over all local sides
    DO iSide=1,6
      IF(ElemToSide(E2S_FLIP,iSide,iElem)==0)THEN ! only master sides
        SideID=ElemToSide(E2S_SIDE_ID,iSide,iElem)
        ! first search only planes with normal vector parallel to gyrotron axis
        IF(( NormVec(1,0,0,SideID) < PoyntingIntCoordErr) .AND. &
           ( NormVec(2,0,0,SideID) < PoyntingIntCoordErr) .AND. &
           ( ABS(NormVec(3,0,0,SideID)) > PoyntingIntCoordErr))THEN
        ! loop over all Points on Face
          DO q=0,PP_N
            DO p=0,PP_N
              diff = ABS(Face_xGP(3,p,q,SideID) - PosPoyntingInt(iPlane))
              IF (diff < PoyntingIntCoordErr) THEN
                IF (.NOT.isPoyntingIntSide(SideID)) THEN
                  !print*,Face_xGP(:,p,q,SideID),SideID
                  nPoyntingIntSides = nPoyntingIntSides +1
                  whichPoyntingPlane(SideID) = iPlane
                  isPoyntingIntSide(SideID) = .TRUE.
                  nFaces(iPlane) = nFaces(iPlane) + 1
                END IF
              !EXIT
              END IF ! diff < eps
            END DO !p
            IF (diff < PoyntingIntCoordErr) THEN
            ! EXIT
            END IF
          END DO !q
        END IF ! n parallel gyrotron axis
      END IF ! flip = 0 master side
    END DO ! iSides
  END DO !iElem=1,nElems
END DO ! iPlanes

#ifdef MPI
ALLOCATE(sumFaces(nPoyntingIntPlanes))
sumFaces=0
sumAllFaces=0
  CALL MPI_ALLREDUCE(nFaces , sumFaces , nPoyntingIntPlanes , MPI_INTEGER, MPI_SUM, PMPIVAR%COMM, IERROR)
  nFaces(:) = sumFaces(:)
  CALL MPI_ALLREDUCE(nPoyntingIntSides , sumAllFaces , 1 , MPI_INTEGER, MPI_SUM, PMPIVAR%COMM, IERROR)
  nPoyntingIntSides = sumAllFaces
#endif /* MPI */

DO iPlane= 1, nPoyntingIntPlanes
  SWRITE(UNIT_stdOut,'(A,I2,A,I10,A)') 'Processed plane no.: ',iPlane,'. Found ',nFaces(iPlane),' surfaces.'
END DO
SWRITE(UNIT_stdOut,'(A,I10,A)') 'A total of',nPoyntingIntSides,' surfaces for the poynting vector integral calculation are found.'

ALLOCATE(S(1:3,0:PP_N,0:PP_N,1:nPoyntingIntSides) , &
         STEM(0:PP_N,0:PP_N,1:nPoyntingIntSides)  )

SWRITE(UNIT_stdOut,'(A)') ' ... POYNTING VECTOR INTEGRAL INITIALIZATION DONE.'  

END SUBROUTINE GetPoyntingIntPlane

SUBROUTINE FinalizePoyntingInt()
!===================================================================================================================================
! Finalize Poynting Integral
!===================================================================================================================================
! MODULES
USE MOD_Mesh_Vars         ,ONLY:isPoyntingIntSide
USE MOD_Analyze_Vars      ,ONLY:PosPoyntingInt,PoyntingIntPlaneFactor, S, STEM
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
! DEALLOCATE ALL
SDEALLOCATE(isPoyntingIntSide)
SDEALLOCATE(PosPoyntingInt)
SDEALLOCATE(PoyntingIntPlaneFactor)
SDEALLOCATE(S)
SDEALLOCATE(STEM)

END SUBROUTINE FinalizePoyntingInt


END MODULE MOD_PoyntingInt