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

MODULE MOD_PICDepo_Shapefunction_Tools
!===================================================================================================================================
! MOD PIC Depo
!===================================================================================================================================
IMPLICIT NONE
PRIVATE
!===================================================================================================================================
INTERFACE calcSfSource
  MODULE PROCEDURE calcSfSource
END INTERFACE

PUBLIC:: calcSfSource
!===================================================================================================================================

CONTAINS

SUBROUTINE calcSfSource(SourceSize_in,ChargeMPF,PartPos,PartID,PartVelo)
!============================================================================================================================
! deposit charges on DOFs via shapefunction including periodic displacements and mirroring
!============================================================================================================================
! use MODULES
USE MOD_Globals
USE MOD_PICDepo_Vars       ,ONLY: DepositionType,dim_sf,dim_sf_dir,dim_sf_dir1,dim_sf_dir2,dim_periodic_vec1,dim_periodic_vec2
USE MOD_Particle_Mesh_Vars ,ONLY: PeriodicSFCaseMatrix,NbrOfPeriodicSFCases
USE MOD_Particle_Mesh_Vars ,ONLY: GEO
!-----------------------------------------------------------------------------------------------------------------------------------
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER, INTENT(IN)              :: SourceSize_in
REAL, INTENT(IN)                 :: ChargeMPF,PartPos(3)
INTEGER, INTENT(IN)              :: PartID
REAL, INTENT(IN), OPTIONAL       :: PartVelo(3)
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!#if ((USE_HDG) && (PP_nVar==1))
!yes, PartVelo and SourceSize_in are not used, but the subroutine-call and -head would be ugly with the preproc-flags...
!INTEGER, PARAMETER               :: SourceSize=1
!REAL                             :: Fac(4:4)
!#else
INTEGER                          :: SourceSize
REAL                             :: Fac(4-SourceSize_in+1:4)
!#endif
INTEGER           :: I,iCase
!REAL                             :: ShiftedPart(1:3), caseShiftedPart(1:3), n_loc(1:3)
REAL              :: PartPosShifted(1:3)
!----------------------------------------------------------------------------------------------------------------------------------
!#if !((USE_HDG) && (PP_nVar==1))
SourceSize=SourceSize_in
!#endif
IF (SourceSize.EQ.1) THEN
  Fac= ChargeMPF
!#if !((USE_HDG) && (PP_nVar==1))
ELSE IF (SourceSize.EQ.4) THEN
  Fac(1:3) = PartVelo*ChargeMPF
  Fac(4)= ChargeMPF
!#endif
ELSE
  CALL abort(&
__STAMP__ &
,'SourceSize has to be either 1 or 4!',SourceSize)
END IF

! Select dimension of shape function
SELECT CASE (dim_sf)
CASE (1)! 1D shape function

  ! NbrOfPeriodicSFCases is either 1 (no periodic vectors: 0) or 3=2+1 (one periodic vector: -1 0 +1) cases
  DO iCase = 1, NbrOfPeriodicSFCases
    IF(NbrOfPeriodicSFCases.GT.1)THEN
      PartPosShifted = (/0., 0., 0./)
      PartPosShifted(dim_sf_dir) = PartPos(dim_sf_dir) + PeriodicSFCaseMatrix(iCase,1)*GEO%PeriodicVectors(dim_sf_dir,dim_sf_dir)
    ELSE
      PartPosShifted(1:3) = PartPos(1:3)
    END IF ! NbrOfPeriodicSFCases.EQ.1
    !IPWRITE(UNIT_StdOut,*) "PartPosShifted =", PartPosShifted
    SELECT CASE(TRIM(DepositionType))
    CASE('shape_function')
      CALL depoChargeOnDOFsSF1D(PartPosShifted,SourceSize,Fac)
    CASE('shape_function_cc')
      CALL depoChargeOnDOFsSFChargeCon1D(PartPosShifted,SourceSize,Fac)
    CASE('shape_function_adaptive')
      CALL depoChargeOnDOFsSFAdaptive1D(PartPosShifted,SourceSize,Fac,PartID)
    CASE DEFAULT
      CALL CollectiveStop(__STAMP__,&
          'Unknown ShapeFunction Method!')
    END SELECT ! DepositionType
  END DO ! iCase = 1, NbrOfPeriodicSFCases

CASE (2)! 2D shape function
  ! NbrOfPeriodicSFCases is either 1 (no periodic vectors: 0) or 9=8+1 (two periodic vectors) cases
  DO iCase = 1, NbrOfPeriodicSFCases
    ! Check if periodic sides are present
    IF(NbrOfPeriodicSFCases.GT.1)THEN
      ! Constant deposition direction
      PartPosShifted(dim_sf_dir) = PartPos(dim_sf_dir)

      ! 1st periodic vector
      ! 1st deposition direction
      PartPosShifted(dim_sf_dir1) = PartPos(dim_sf_dir1)&
                                  + PeriodicSFCaseMatrix(iCase,1)*GEO%PeriodicVectors(dim_sf_dir1,dim_periodic_vec1)
      ! 2nd deposition direction
      PartPosShifted(dim_sf_dir2) = PartPos(dim_sf_dir2)&
                                  + PeriodicSFCaseMatrix(iCase,1)*GEO%PeriodicVectors(dim_sf_dir2,dim_periodic_vec1)

      ! 2nd periodic vector (if available)
      IF(dim_periodic_vec2.GT.0)THEN
        ! 1st deposition direction
        PartPosShifted(dim_sf_dir1) = PartPosShifted(dim_sf_dir1)&
                                    + PeriodicSFCaseMatrix(iCase,2)*GEO%PeriodicVectors(dim_sf_dir1,dim_periodic_vec2)
        ! 2nd deposition direction
        PartPosShifted(dim_sf_dir2) = PartPosShifted(dim_sf_dir2)&
                                    + PeriodicSFCaseMatrix(iCase,2)*GEO%PeriodicVectors(dim_sf_dir2,dim_periodic_vec2)
      END IF ! dim_periodic_vec2.GT.0
    ELSE
      PartPosShifted(1:3) = PartPos(1:3)
    END IF ! NbrOfPeriodicSFCases.EQ.1

    SELECT CASE(TRIM(DepositionType))
    CASE('shape_function')
      CALL depoChargeOnDOFsSF2D(PartPosShifted,SourceSize,Fac)
    CASE('shape_function_cc')
      CALL depoChargeOnDOFsSFChargeCon2D(PartPosShifted,SourceSize,Fac)
    CASE('shape_function_adaptive')
      CALL abort(&
          __STAMP__&
          ,'Not implemented [shape_function_adaptive] for 2D.')
    CASE DEFAULT
      CALL CollectiveStop(__STAMP__,&
          'Unknown ShapeFunction Method!')
    END SELECT ! DepositionType
  END DO ! iCase = 1, NbrOfPeriodicSFCases

CASE DEFAULT!CASE(3) Standard 3D shape function
  ! NbrOfPeriodicSFCases is either 1 (no periodic vectors: 0) or 27=26+1 (three periodic vectors) cases
  DO iCase = 1, NbrOfPeriodicSFCases
    ! Check if periodic sides are present
    IF(NbrOfPeriodicSFCases.GT.1)THEN
      DO I = 1,3
        PartPosShifted(I) = PartPos(I)&
            + PeriodicSFCaseMatrix(iCase,1)*GEO%PeriodicVectors(I,1)&
            + PeriodicSFCaseMatrix(iCase,2)*GEO%PeriodicVectors(I,2)&
            + PeriodicSFCaseMatrix(iCase,3)*GEO%PeriodicVectors(I,3)
      END DO
    ELSE
      PartPosShifted(1:3) = PartPos(1:3)
    END IF ! NbrOfPeriodicSFCases.EQ.1
    ! Select deposition type
    SELECT CASE(TRIM(DepositionType))
    CASE('shape_function')
      CALL depoChargeOnDOFsSF(PartPosShifted,SourceSize,Fac)
    CASE('shape_function_cc')
      CALL depoChargeOnDOFsSFChargeCon(PartPosShifted,SourceSize,Fac)
    CASE('shape_function_adaptive')
      CALL depoChargeOnDOFsSFAdaptive(PartPosShifted,SourceSize,Fac,PartID)
    CASE DEFAULT
      CALL CollectiveStop(__STAMP__,&
          'Unknown ShapeFunction Method!')
    END SELECT ! DepositionType
  END DO ! iCase = 1, NbrOfPeriodicSFCases
END SELECT 


!  END DO ! iCase (periodicity)

END SUBROUTINE calcSfSource


SUBROUTINE depoChargeOnDOFsSF_RGetAccumulate(Position,SourceSize,Fac)
!============================================================================================================================
! actual deposition of single charge on DOFs via shapefunction
!============================================================================================================================
! use MODULES
USE MOD_Globals
USE MOD_PICDepo_Vars,           ONLY:PartSource, r_sf, r2_sf, r2_sf_inv, alpha_sf
USE MOD_Mesh_Vars,              ONLY:nElems,offSetElem
USE MOD_Particle_Mesh_Vars,     ONLY:GEO,ElemBaryNgeo, FIBGM_offsetElem, FIBGM_nElems, FIBGM_Element, Elem_xGP_Shared
USE MOD_Particle_Mesh_Vars,     ONLY:ElemRadiusNGeo
USE MOD_Preproc
USE MOD_Mesh_Tools,             ONLY: GetCNElemID
#if USE_MPI
USE MOD_PICDepo_Vars,           ONLY:PartSource_Shared_Win
USE MOD_MPI_Shared_Vars,        ONLY:nComputeNodeTotalElems
#endif /*USE_MPI*/
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars,       ONLY:nDeposPerElem
#endif  /*USE_LOADBALANCE*/
!-----------------------------------------------------------------------------------------------------------------------------------
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                 :: Position(3)
INTEGER, INTENT(IN)              :: SourceSize
!#if ((USE_HDG) && (PP_nVar==1))
!REAL, INTENT(IN)                 :: Fac(4:4)
!#else
REAL, INTENT(IN)                 :: Fac(4-SourceSize+1:4)
!#endif
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                          :: k, l, m
INTEGER                          :: kmin, kmax, lmin, lmax, mmin, mmax
INTEGER                          :: kk, ll, mm, ppp
INTEGER                          :: globElemID, CNElemID
REAL                             :: radius2, S, S1
REAL                             :: PartSourceLoc(4-SourceSize+1:4,0:PP_N,0:PP_N,0:PP_N)
INTEGER                          :: PartSourceSize, PartSourceSizeTarget, Request
INTEGER                          :: expo
#if USE_MPI
LOGICAL                          :: chargedone(1:nComputeNodeTotalElems)
#else
LOGICAL                          :: chargedone(1:nElems)
#endif /*USE_MPI*/
!----------------------------------------------------------------------------------------------------------------------------------
PartSourceSize =  SourceSize*(PP_N+1)**3
#if USE_MPI
PartSourceSizeTarget = 4*(PP_N+1)**3*nComputeNodeTotalElems
#else
PartSourceSizeTarget = 4*(PP_N+1)**3*nElems
#endif /*USE_MPI*/
chargedone(:) = .FALSE.
!-- determine which background mesh cells (and interpolation points within) need to be considered
kmax = CEILING((Position(1)+r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1))
kmax = MIN(kmax,GEO%FIBGMimax)
kmin = FLOOR((Position(1)-r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1)+1)
kmin = MAX(kmin,GEO%FIBGMimin)
lmax = CEILING((Position(2)+r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2))
lmax = MIN(lmax,GEO%FIBGMjmax)
lmin = FLOOR((Position(2)-r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2)+1)
lmin = MAX(lmin,GEO%FIBGMjmin)
mmax = CEILING((Position(3)+r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3))
mmax = MIN(mmax,GEO%FIBGMkmax)
mmin = FLOOR((Position(3)-r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3)+1)
mmin = MAX(mmin,GEO%FIBGMkmin)
DO kk = kmin,kmax
  DO ll = lmin, lmax
    DO mm = mmin, mmax
      !--- go through all mapped elements not done yet
      DO ppp = 1,FIBGM_nElems(kk,ll,mm)
        globElemID = FIBGM_Element(FIBGM_offsetElem(kk,ll,mm)+ppp)
        CNElemID = GetCNElemID(globElemID)
        IF (chargedone(CNElemID)) CYCLE
        IF (VECNORM(Position(1:3)-ElemBaryNgeo(1:3,CNElemID)).GT.(r_sf+ElemRadiusNGeo(CNElemID))) CYCLE
#if USE_LOADBALANCE
        ! loadbalance for halo region?
        IF (((globElemID-offSetElem).GE.1).AND.(globElemID-offSetElem).LE.nElems) &
          nDeposPerElem(globElemID-offSetElem)=nDeposPerElem(globElemID-offSetElem)+1
#endif /*USE_LOADBALANCE*/
          !--- go through all gauss points
        PartSourceLoc = 0.0
        DO m=0,PP_N; DO l=0,PP_N; DO k=0,PP_N
          !-- calculate distance between gauss and particle
          radius2 = SUM((Position(1:3) - Elem_xGP_Shared(1:3,k,l,m,globElemID))**2.)
          !-- calculate charge and current density at ip point using a shape function
          !-- currently only one shapefunction available, more to follow (including structure change)
          IF (radius2 .LE. r2_sf) THEN
            S = 1. - r2_sf_inv * radius2
            S1 = S*S
            DO expo = 3, alpha_sf
              S1 = S*S1
            END DO
            IF (SourceSize.EQ.1) THEN
              PartSourceLoc(4,k,l,m) = PartSourceLoc(4,k,l,m) + Fac(4) * S1
!#if !((USE_HDG) && (PP_nVar==1))
            ELSE IF (SourceSize.EQ.4) THEN
              PartSourceLoc(1:4,k,l,m) = PartSourceLoc(1:4,k,l,m) + Fac(1:4) * S1
!#endif
            END IF
          END IF
        END DO; END DO; END DO
        chargedone(CNElemID) = .TRUE.
#if USE_MPI
!        CALL MPI_WIN_LOCK(MPI_LOCK_EXCLUSIVE,0,MPI_INFO_NULL,PartSource_Shared_Win, IERROR)
        CALL MPI_RGet_accumulate(PartSourceLoc(4-SourceSize+1:4,:,:,:),            PartSourceSize       ,MPI_DOUBLE_PRECISION, &
                                 PartSource(   4-SourceSize+1  ,0,0,0,globElemID), PartSourceSizeTarget, MPI_DOUBLE_PRECISION, 0, &
            INT((4-SourceSize+1)*(PP_N+1)**3*(globElemID-1),MPI_ADDRESS_KIND)*MPI_ADDRESS_KIND, &
            PartSourceSize, MPI_DOUBLE_PRECISION, MPI_SUM, PartSource_Shared_Win,Request, IERROR)
!        CALL MPI_WAIT(Request, MPI_STATUS_IGNORE, IERROR)
!         CALL MPI_WIN_UNLOCK_ALL(0,PartSource_Shared_Win, IERROR)
!        PartSource(4-SourceSize+1:4,:,:,:,globElemID) = PartSource(4-SourceSize+1:4,:,:,:,globElemID) &
!            + PartSourceLoc(4-SourceSize+1:4,:,:,:)
!        CALL MPI_Win_flush(0,PartSource_Shared_Win, IERROR)
#else
        PartSource(4-SourceSize+1:4,:,:,:,globElemID) = PartSource(4-SourceSize+1:4,:,:,:,globElemID) &
            + PartSourceLoc(4-SourceSize+1:4,:,:,:)
#endif
      END DO ! ppp
    END DO ! mm
  END DO ! ll
END DO ! kk

END SUBROUTINE depoChargeOnDOFsSF_RGetAccumulate


SUBROUTINE depoChargeOnDOFsSF(Position,SourceSize,Fac)
!============================================================================================================================
! actual deposition of single charge on DOFs via shapefunction
!============================================================================================================================
! use MODULES
USE MOD_Globals
USE MOD_PICDepo_Vars,           ONLY:r_sf,r2_sf,r2_sf_inv,alpha_sf,PartSource
USE MOD_Mesh_Vars,              ONLY:nElems,offSetElem
USE MOD_Particle_Mesh_Vars,     ONLY:GEO,ElemBaryNgeo,FIBGM_offsetElem,FIBGM_nElems,FIBGM_Element,Elem_xGP_Shared
USE MOD_Particle_Mesh_Vars,     ONLY:ElemRadiusNGeo
USE MOD_Preproc
USE MOD_Mesh_Tools,             ONLY:GetCNElemID
#if USE_MPI
USE MOD_MPI_Shared_Vars,        ONLY:nComputeNodeTotalElems
USE MOD_PICDepo_Vars,           ONLY:PartSourceProc
USE MOD_PICDepo_Vars,           ONLY:SendElemShapeID
#endif /*USE_MPI*/
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars,       ONLY:nDeposPerElem
#endif  /*USE_LOADBALANCE*/
!-----------------------------------------------------------------------------------------------------------------------------------
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                 :: Position(3)
INTEGER, INTENT(IN)              :: SourceSize
!#if ((USE_HDG) && (PP_nVar==1))
!REAL, INTENT(IN)                 :: Fac(4:4)
!#else
REAL, INTENT(IN)                 :: Fac(4-SourceSize+1:4)
!#endif
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                          :: k, l, m
INTEGER                          :: kmin, kmax, lmin, lmax, mmin, mmax
INTEGER                          :: kk, ll, mm, ppp
INTEGER                          :: globElemID, CNElemID
REAL                             :: radius2, S, S1
INTEGER                          :: expo, nUsedElems,I
#if USE_MPI
LOGICAL                          :: chargedone(1:nComputeNodeTotalElems)
!INTEGER                          :: usedElems(   nComputeNodeTotalElems)
#else
LOGICAL                          :: chargedone(1:nElems)
!INTEGER                          :: usedElems(   nElems)
#endif /*USE_MPI*/
!----------------------------------------------------------------------------------------------------------------------------------
I=5-SourceSize
chargedone(:) = .FALSE.
nUsedElems = 0
!-- determine which background mesh cells (and interpolation points within) need to be considered
kmax = CEILING((Position(1)+r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1))
kmax = MIN(kmax,GEO%FIBGMimax)
kmin = FLOOR((Position(1)-r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1)+1)
kmin = MAX(kmin,GEO%FIBGMimin)
lmax = CEILING((Position(2)+r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2))
lmax = MIN(lmax,GEO%FIBGMjmax)
lmin = FLOOR((Position(2)-r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2)+1)
lmin = MAX(lmin,GEO%FIBGMjmin)
mmax = CEILING((Position(3)+r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3))
mmax = MIN(mmax,GEO%FIBGMkmax)
mmin = FLOOR((Position(3)-r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3)+1)
mmin = MAX(mmin,GEO%FIBGMkmin)
DO kk = kmin,kmax
  DO ll = lmin, lmax
    DO mm = mmin, mmax
      !--- go through all mapped elements not done yet
      DO ppp = 1,FIBGM_nElems(kk,ll,mm)
        globElemID = FIBGM_Element(FIBGM_offsetElem(kk,ll,mm)+ppp)
        CNElemID = GetCNElemID(globElemID)
        IF (chargedone(CNElemID)) CYCLE
        IF (VECNORM(Position(1:3)-ElemBaryNgeo(1:3,CNElemID)).GT.(r_sf+ElemRadiusNGeo(CNElemID))) CYCLE
#if USE_LOADBALANCE
        IF (((globElemID-offSetElem).GE.1).AND.(globElemID-offSetElem).LE.nElems) &
          nDeposPerElem(globElemID-offSetElem)=nDeposPerElem(globElemID-offSetElem)+1
#endif /*USE_LOADBALANCE*/
          !--- go through all gauss points
        DO m=0,PP_N; DO l=0,PP_N; DO k=0,PP_N
          !-- calculate distance between gauss and particle
          radius2 = SUM((Position(1:3) - Elem_xGP_Shared(1:3,k,l,m,globElemID))**2.)
          !-- calculate charge and current density at ip point using a shape function
          !-- currently only one shapefunction available, more to follow (including structure change)
          IF (radius2 .LE. r2_sf) THEN
!            nUsedElems = nUsedElems + 1
!            usedElems(nUsedElems) = CNElemID
            S = 1. - r2_sf_inv * radius2
            S1 = S*S
            DO expo = 3, alpha_sf
              S1 = S*S1
            END DO

#if USE_MPI
            IF (((globElemID-offSetElem).GE.1).AND.(globElemID-offSetElem).LE.nElems) THEN
#endif /*USE_MPI*/
              PartSource(I:4,k,l,m, CNElemID) = PartSource(I:4,k,l,m, CNElemID) + Fac(4) * S1
  !#if !((USE_HDG) && (PP_nVar==1))
  !#endif
#if USE_MPI
            ELSE
              ASSOCIATE( ShapeID => SendElemShapeID(CNElemID))
                PartSourceProc(I:4,k,l,m, ShapeID) = PartSourceProc(I:4,k,l,m, ShapeID) + Fac(4) * S1
              END ASSOCIATE
  !#if !((USE_HDG) && (PP_nVar==1))
  !#endif
            END IF
#endif /*USE_MPI*/
          END IF
        END DO; END DO; END DO
        chargedone(CNElemID) = .TRUE.
      END DO ! ppp
    END DO ! mm
  END DO ! ll
END DO ! kk
END SUBROUTINE depoChargeOnDOFsSF


SUBROUTINE depoChargeOnDOFsSF1D(Position,SourceSize,Fac)
!============================================================================================================================
! actual deposition of single charge on DOFs via shapefunction
!============================================================================================================================
! use MODULES
USE MOD_Globals
USE MOD_PICDepo_Vars,           ONLY:r_sf,r2_sf,r2_sf_inv,alpha_sf,PartSource,dim_sf_dir
USE MOD_Mesh_Vars,              ONLY:nElems,offSetElem
USE MOD_Particle_Mesh_Vars,     ONLY:GEO,ElemBaryNgeo,FIBGM_offsetElem,FIBGM_nElems,FIBGM_Element,Elem_xGP_Shared
USE MOD_Particle_Mesh_Vars,     ONLY:ElemRadiusNGeo
USE MOD_Preproc
USE MOD_Mesh_Tools,             ONLY:GetCNElemID
#if USE_MPI
USE MOD_MPI_Shared_Vars,        ONLY:nComputeNodeTotalElems
USE MOD_PICDepo_Vars,           ONLY:PartSourceProc,SendElemShapeID
#endif /*USE_MPI*/
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars,       ONLY:nDeposPerElem
#endif  /*USE_LOADBALANCE*/
!-----------------------------------------------------------------------------------------------------------------------------------
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                 :: Position(3)
INTEGER, INTENT(IN)              :: SourceSize
!#if ((USE_HDG) && (PP_nVar==1))
!REAL, INTENT(IN)                 :: Fac(4:4)
!#else
REAL, INTENT(IN)                 :: Fac(4-SourceSize+1:4)
!#endif
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                          :: k, l, m
INTEGER                          :: kmin, kmax, lmin, lmax, mmin, mmax
INTEGER                          :: kk, ll, mm, ppp
INTEGER                          :: globElemID, CNElemID
REAL                             :: radius2, S, S1
INTEGER                          :: expo, nUsedElems
#if USE_MPI
LOGICAL                          :: chargedone(1:nComputeNodeTotalElems)
!INTEGER                          :: usedElems(   nComputeNodeTotalElems)
#else
LOGICAL                          :: chargedone(1:nElems)
!INTEGER                          :: usedElems(   nElems)
#endif /*USE_MPI*/
!----------------------------------------------------------------------------------------------------------------------------------
chargedone(:) = .FALSE.
nUsedElems = 0
!-- determine which background mesh cells (and interpolation points within) need to be considered
kmax = CEILING((Position(1)+r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1))
kmax = MIN(kmax,GEO%FIBGMimax)
kmin = FLOOR((Position(1)-r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1)+1)
kmin = MAX(kmin,GEO%FIBGMimin)
lmax = CEILING((Position(2)+r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2))
lmax = MIN(lmax,GEO%FIBGMjmax)
lmin = FLOOR((Position(2)-r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2)+1)
lmin = MAX(lmin,GEO%FIBGMjmin)
mmax = CEILING((Position(3)+r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3))
mmax = MIN(mmax,GEO%FIBGMkmax)
mmin = FLOOR((Position(3)-r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3)+1)
mmin = MAX(mmin,GEO%FIBGMkmin)
DO kk = kmin,kmax
  DO ll = lmin, lmax
    DO mm = mmin, mmax
      !--- go through all mapped elements not done yet
      DO ppp = 1,FIBGM_nElems(kk,ll,mm)
        globElemID = FIBGM_Element(FIBGM_offsetElem(kk,ll,mm)+ppp)
        CNElemID = GetCNElemID(globElemID)
        IF (chargedone(CNElemID)) CYCLE
        IF (ABS(Position(dim_sf_dir)-ElemBaryNgeo(dim_sf_dir,CNElemID)).GT.(r_sf+ElemRadiusNGeo(CNElemID))) CYCLE
#if USE_LOADBALANCE
        IF (((globElemID-offSetElem).GE.1).AND.(globElemID-offSetElem).LE.nElems) &
          nDeposPerElem(globElemID-offSetElem)=nDeposPerElem(globElemID-offSetElem)+1
#endif /*USE_LOADBALANCE*/
          !--- go through all gauss points
        DO m=0,PP_N; DO l=0,PP_N; DO k=0,PP_N
          !-- calculate distance between gauss and particle
          radius2 = (Position(dim_sf_dir) - Elem_xGP_Shared(dim_sf_dir,k,l,m,globElemID))**2.
          !-- calculate charge and current density at ip point using a shape function
          !-- currently only one shapefunction available, more to follow (including structure change)
          IF (radius2 .LE. r2_sf) THEN
!            nUsedElems = nUsedElems + 1
!            usedElems(nUsedElems) = CNElemID
            S = 1. - r2_sf_inv * radius2
            S1 = S*S
            DO expo = 3, alpha_sf
              S1 = S*S1
            END DO

#if USE_MPI
            IF (((globElemID-offSetElem).GE.1).AND.(globElemID-offSetElem).LE.nElems) THEN
#endif /*USE_MPI*/
              IF (SourceSize.EQ.1) THEN
                PartSource(4,k,l,m, CNElemID) = PartSource(4,k,l,m, CNElemID) + Fac(4) * S1
  !#if !((USE_HDG) && (PP_nVar==1))
              ELSE IF (SourceSize.EQ.4) THEN
                PartSource(1:4,k,l,m, CNElemID) = PartSource(1:4,k,l,m, CNElemID) + Fac(1:4) * S1
  !#endif
              END IF
#if USE_MPI
            ELSE
              IF (SourceSize.EQ.1) THEN
                PartSourceProc(4,k,l,m, SendElemShapeID(CNElemID)) =  &
                    PartSourceProc(4,k,l,m, SendElemShapeID(CNElemID)) + Fac(4) * S1
  !#if !((USE_HDG) && (PP_nVar==1))
              ELSE IF (SourceSize.EQ.4) THEN
                PartSourceProc(1:4,k,l,m, SendElemShapeID(CNElemID)) = &
                    PartSourceProc(1:4,k,l,m, SendElemShapeID(CNElemID)) + Fac(1:4) * S1
  !#endif
              END IF
            END IF
#endif /*USE_MPI*/
          END IF
        END DO; END DO; END DO
        chargedone(CNElemID) = .TRUE.
      END DO ! ppp
    END DO ! mm
  END DO ! ll
END DO ! kk
END SUBROUTINE depoChargeOnDOFsSF1D


SUBROUTINE depoChargeOnDOFsSF2D(Position,SourceSize,Fac)
!============================================================================================================================
! actual deposition of single charge on DOFs via shapefunction
!============================================================================================================================
! use MODULES
USE MOD_Globals
USE MOD_PICDepo_Vars,           ONLY:r_sf,r2_sf,r2_sf_inv,alpha_sf,PartSource,dim_sf_dir1,dim_sf_dir2
USE MOD_Mesh_Vars,              ONLY:nElems,offSetElem
USE MOD_Particle_Mesh_Vars,     ONLY:GEO,ElemBaryNgeo,FIBGM_offsetElem,FIBGM_nElems,FIBGM_Element,Elem_xGP_Shared
USE MOD_Particle_Mesh_Vars,     ONLY:ElemRadiusNGeo
USE MOD_Preproc
USE MOD_Mesh_Tools,             ONLY:GetCNElemID
#if USE_MPI
USE MOD_MPI_Shared_Vars,        ONLY:nComputeNodeTotalElems
USE MOD_PICDepo_Vars,           ONLY:PartSourceProc,SendElemShapeID
#endif /*USE_MPI*/
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars,       ONLY:nDeposPerElem
#endif  /*USE_LOADBALANCE*/
!-----------------------------------------------------------------------------------------------------------------------------------
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                 :: Position(3)
INTEGER, INTENT(IN)              :: SourceSize
!#if ((USE_HDG) && (PP_nVar==1))
!REAL, INTENT(IN)                 :: Fac(4:4)
!#else
REAL, INTENT(IN)                 :: Fac(4-SourceSize+1:4)
!#endif
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                          :: k, l, m
INTEGER                          :: kmin, kmax, lmin, lmax, mmin, mmax
INTEGER                          :: kk, ll, mm, ppp
INTEGER                          :: globElemID, CNElemID
REAL                             :: radius2, S, S1
INTEGER                          :: expo, nUsedElems
#if USE_MPI
LOGICAL                          :: chargedone(1:nComputeNodeTotalElems)
!INTEGER                          :: usedElems(   nComputeNodeTotalElems)
#else
LOGICAL                          :: chargedone(1:nElems)
!INTEGER                          :: usedElems(   nElems)
#endif /*USE_MPI*/
!----------------------------------------------------------------------------------------------------------------------------------
chargedone(:) = .FALSE.
nUsedElems = 0
!-- determine which background mesh cells (and interpolation points within) need to be considered
kmax = CEILING((Position(1)+r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1))
kmax = MIN(kmax,GEO%FIBGMimax)
kmin = FLOOR((Position(1)-r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1)+1)
kmin = MAX(kmin,GEO%FIBGMimin)
lmax = CEILING((Position(2)+r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2))
lmax = MIN(lmax,GEO%FIBGMjmax)
lmin = FLOOR((Position(2)-r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2)+1)
lmin = MAX(lmin,GEO%FIBGMjmin)
mmax = CEILING((Position(3)+r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3))
mmax = MIN(mmax,GEO%FIBGMkmax)
mmin = FLOOR((Position(3)-r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3)+1)
mmin = MAX(mmin,GEO%FIBGMkmin)
DO kk = kmin,kmax
  DO ll = lmin, lmax
    DO mm = mmin, mmax
      !--- go through all mapped elements not done yet
      DO ppp = 1,FIBGM_nElems(kk,ll,mm)
        globElemID = FIBGM_Element(FIBGM_offsetElem(kk,ll,mm)+ppp)
        CNElemID = GetCNElemID(globElemID)
        IF (chargedone(CNElemID)) CYCLE
        ! Pick the opposite directions of dim_sf_dir in the 2D case via MERGE(...)
        IF (SQRT((Position(dim_sf_dir1)-ElemBaryNgeo(dim_sf_dir1,CNElemID))**2+&
                 (Position(dim_sf_dir2)-ElemBaryNgeo(dim_sf_dir2,CNElemID))**2).GT.(r_sf+ElemRadiusNGeo(CNElemID))) CYCLE
#if USE_LOADBALANCE
        IF (((globElemID-offSetElem).GE.1).AND.(globElemID-offSetElem).LE.nElems) &
          nDeposPerElem(globElemID-offSetElem)=nDeposPerElem(globElemID-offSetElem)+1
#endif /*USE_LOADBALANCE*/
          !--- go through all gauss points
        DO m=0,PP_N; DO l=0,PP_N; DO k=0,PP_N
          !-- calculate distance between gauss and particle
          ! Pick the opposite directions of dim_sf_dir in the 2D case via MERGE(...)
          radius2 = (Position(dim_sf_dir1) - Elem_xGP_Shared(dim_sf_dir1,k,l,m,globElemID))**2.+&
                    (Position(dim_sf_dir2) - Elem_xGP_Shared(dim_sf_dir2,k,l,m,globElemID))**2.
          !-- calculate charge and current density at ip point using a shape function
          !-- currently only one shapefunction available, more to follow (including structure change)
          IF (radius2 .LE. r2_sf) THEN
!            nUsedElems = nUsedElems + 1
!            usedElems(nUsedElems) = CNElemID
            S = 1. - r2_sf_inv * radius2
            S1 = S*S
            DO expo = 3, alpha_sf
              S1 = S*S1
            END DO

#if USE_MPI
            IF (((globElemID-offSetElem).GE.1).AND.(globElemID-offSetElem).LE.nElems) THEN
#endif /*USE_MPI*/
              IF (SourceSize.EQ.1) THEN
                PartSource(4,k,l,m, CNElemID) = PartSource(4,k,l,m, CNElemID) + Fac(4) * S1
  !#if !((USE_HDG) && (PP_nVar==1))
              ELSE IF (SourceSize.EQ.4) THEN
                PartSource(1:4,k,l,m, CNElemID) = PartSource(1:4,k,l,m, CNElemID) + Fac(1:4) * S1
  !#endif
              END IF
#if USE_MPI
            ELSE
              IF (SourceSize.EQ.1) THEN
                PartSourceProc(4,k,l,m, SendElemShapeID(CNElemID)) =  &
                    PartSourceProc(4,k,l,m, SendElemShapeID(CNElemID)) + Fac(4) * S1
  !#if !((USE_HDG) && (PP_nVar==1))
              ELSE IF (SourceSize.EQ.4) THEN
                PartSourceProc(1:4,k,l,m, SendElemShapeID(CNElemID)) = &
                    PartSourceProc(1:4,k,l,m, SendElemShapeID(CNElemID)) + Fac(1:4) * S1
  !#endif
              END IF
            END IF
#endif /*USE_MPI*/
          END IF
        END DO; END DO; END DO
        chargedone(CNElemID) = .TRUE.
      END DO ! ppp
    END DO ! mm
  END DO ! ll
END DO ! kk
END SUBROUTINE depoChargeOnDOFsSF2D


SUBROUTINE depoChargeOnDOFsSFChargeCon(Position,SourceSize,Fac)
!============================================================================================================================
! actual deposition of single charge on DOFs via shapefunction
!============================================================================================================================
! use MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_PICDepo_Vars,           ONLY:r_sf, r2_sf, r2_sf_inv,alpha_sf,PartSource,w_sf
USE MOD_Mesh_Vars,              ONLY:nElems, offSetElem
USE MOD_Particle_Mesh_Vars,     ONLY:GEO, ElemBaryNgeo, FIBGM_offsetElem, FIBGM_nElems, FIBGM_Element, Elem_xGP_Shared
USE MOD_Particle_Mesh_Vars,     ONLY:ElemRadiusNGeo, ElemsJ
USE MOD_Preproc
USE MOD_Mesh_Tools,             ONLY:GetCNElemID
USE MOD_Interpolation_Vars,     ONLY:wGP
#if USE_MPI
USE MOD_MPI_Shared_Vars,        ONLY:nComputeNodeTotalElems
USE MOD_PICDepo_Vars,           ONLY:SendElemShapeID,PartSourceProc
#endif
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars,       ONLY:nDeposPerElem
#endif  /*USE_LOADBALANCE*/
!-----------------------------------------------------------------------------------------------------------------------------------
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                 :: Position(3)
INTEGER, INTENT(IN)              :: SourceSize
!#if ((USE_HDG) && (PP_nVar==1))
!REAL, INTENT(IN)                 :: Fac(4:4)
!#else
REAL, INTENT(IN)                 :: Fac(4-SourceSize+1:4)
!#endif
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
LOGICAL                          :: firstElem,elemDone
INTEGER                          :: k, l, m,I
INTEGER                          :: kmin, kmax, lmin, lmax, mmin, mmax
INTEGER                          :: kk, ll, mm, ppp
INTEGER                          :: globElemID, CNElemID
INTEGER                          :: expo, nUsedElems, localElem
REAL                             :: radius2, S, S1
REAL                             :: totalCharge, alpha
REAL                             :: PartSourcetmp(1:4,0:PP_N,0:PP_N,0:PP_N)
#if USE_MPI
LOGICAL                          :: chargedone(1:nComputeNodeTotalElems)
#else
LOGICAL                          :: chargedone(1:nElems)
#endif /*USE_MPI*/
TYPE SPElem
  REAL, ALLOCATABLE     :: PartSourceLoc(:,:,:,:)
  INTEGER               :: globElemID
  TYPE (SPElem), POINTER :: next => null()
END TYPE
TYPE (SPElem), POINTER :: first => null()
TYPE (SPElem), POINTER :: element
!----------------------------------------------------------------------------------------------------------------------------------
I=5-SourceSize
chargedone(:) = .FALSE.
firstElem = .TRUE.

ALLOCATE(first)
ALLOCATE(first%PartSourceLoc(1:4,0:PP_N,0:PP_N,0:PP_N))
nUsedElems = 0
totalCharge = 0.0
!-- determine which background mesh cells (and interpolation points within) need to be considered
kmax = CEILING((Position(1)+r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1))
kmax = MIN(kmax,GEO%FIBGMimax)
kmin = FLOOR((Position(1)-r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1)+1)
kmin = MAX(kmin,GEO%FIBGMimin)
lmax = CEILING((Position(2)+r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2))
lmax = MIN(lmax,GEO%FIBGMjmax)
lmin = FLOOR((Position(2)-r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2)+1)
lmin = MAX(lmin,GEO%FIBGMjmin)
mmax = CEILING((Position(3)+r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3))
mmax = MIN(mmax,GEO%FIBGMkmax)
mmin = FLOOR((Position(3)-r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3)+1)
mmin = MAX(mmin,GEO%FIBGMkmin)
DO kk = kmin,kmax
  DO ll = lmin, lmax
    DO mm = mmin, mmax
      !--- go through all mapped elements not done yet
      DO ppp = 1,FIBGM_nElems(kk,ll,mm)
        globElemID = FIBGM_Element(FIBGM_offsetElem(kk,ll,mm)+ppp)
        elemDone = .FALSE.
        CNElemID = GetCNElemID(globElemID)
        localElem = globElemID-offSetElem
        IF (chargedone(CNElemID)) CYCLE
        IF (VECNORM(Position(1:3)-ElemBaryNgeo(1:3,CNElemID)).GT.(r_sf+ElemRadiusNGeo(CNElemID))) CYCLE
#if USE_LOADBALANCE
        IF ((localElem.GE.1).AND.localElem.LE.nElems) nDeposPerElem(localElem)=nDeposPerElem(localElem)+1
#endif /*USE_LOADBALANCE*/
          !--- go through all gauss points
        DO m=0,PP_N; DO l=0,PP_N; DO k=0,PP_N
          !-- calculate distance between gauss and particle
          radius2 = SUM((Position(1:3) - Elem_xGP_Shared(1:3,k,l,m,globElemID))**2.)
          !-- calculate charge and current density at ip point using a shape function
          !-- currently only one shapefunction available, more to follow (including structure change)
          IF (radius2 .LE. r2_sf) THEN
            IF (.NOT.elemDone) THEN
              PartSourcetmp = 0.0
              nUsedElems = nUsedElems + 1
              elemDone = .TRUE.
            END IF
            S = 1. - r2_sf_inv * radius2
            S1 = S*S
            DO expo = 3, alpha_sf
              S1 = S*S1
            END DO
            IF (SourceSize.EQ.1) THEN
              PartSourcetmp(4,k,l,m) = Fac(4) * S1
            ELSE
              PartSourcetmp(1:4,k,l,m) = Fac(1:4) * S1
            END IF
            totalCharge = totalCharge  + wGP(k)*wGP(l)*wGP(m)*PartSourcetmp(4,k,l,m)/ElemsJ(k,l,m,CNElemID)
          END IF
        END DO; END DO; END DO

        IF (elemDone) THEN
          IF (firstElem) THEN
            first%PartSourceLoc(:,:,:,:) = PartSourcetmp(:,:,:,:)
            first%globElemID = globElemID
            firstElem = .FALSE.
          ELSE
            ALLOCATE(element)
            ALLOCATE(element%PartSourceLoc(1:4,0:PP_N,0:PP_N,0:PP_N))
            element%next => first%next
            first%next => element
            element%PartSourceLoc(:,:,:,:) = PartSourcetmp(:,:,:,:)
            element%globElemID = globElemID
          END IF
        END IF
        chargedone(CNElemID) = .TRUE.
      END DO ! ppp
    END DO ! mm
  END DO ! ll
END DO ! kk

element => first
firstElem = .TRUE.
IF (nUsedElems.GT.0) THEN
  alpha = (Fac(4)/w_sf) / totalCharge
  DO ppp=1, nUsedElems
    globElemID = element%globElemID
    localElem = globElemID-offSetElem
    CNElemID = GetCNElemID(globElemID)
#if USE_MPI
    IF (((localElem).GE.1).AND.(localElem).LE.nElems) THEN
#endif /*USE_MPI*/
      PartSource(I:4,:,:,:, CNElemID) = PartSource(I:4,:,:,:, CNElemID) + alpha*element%PartSourceLoc(I:4,:,:,:)
#if USE_MPI
    ELSE
      ASSOCIATE( ShapeID => SendElemShapeID(CNElemID) )
        PartSourceProc(I:4,:,:,:, ShapeID) = PartSourceProc(I:4,:,:,:, ShapeID) + alpha * element%PartSourceLoc(I:4,:,:,:)
      END ASSOCIATE
    END IF
#endif /*USE_MPI*/
    first => first%next
    DEALLOCATE(element%PartSourceLoc)
    DEALLOCATE(element)
    element => first
  END DO
END IF

END SUBROUTINE depoChargeOnDOFsSFChargeCon


SUBROUTINE depoChargeOnDOFsSFChargeCon1D(Position,SourceSize,Fac)
!============================================================================================================================
! actual deposition of single charge on DOFs via shapefunction
!============================================================================================================================
! use MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_PICDepo_Vars,           ONLY:r_sf, r2_sf, r2_sf_inv,alpha_sf,PartSource,w_sf,dim_sf_dir
USE MOD_Mesh_Vars,              ONLY:nElems, offSetElem
USE MOD_Particle_Mesh_Vars,     ONLY:GEO, ElemBaryNgeo, FIBGM_offsetElem, FIBGM_nElems, FIBGM_Element, Elem_xGP_Shared
USE MOD_Particle_Mesh_Vars,     ONLY:ElemRadiusNGeo, ElemsJ
USE MOD_Preproc
USE MOD_Mesh_Tools,             ONLY:GetCNElemID
USE MOD_Interpolation_Vars,     ONLY:wGP
#if USE_MPI
USE MOD_MPI_Shared_Vars,        ONLY:nComputeNodeTotalElems
USE MOD_PICDepo_Vars,           ONLY:SendElemShapeID,PartSourceProc
#endif
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars,       ONLY:nDeposPerElem
#endif  /*USE_LOADBALANCE*/
!-----------------------------------------------------------------------------------------------------------------------------------
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                 :: Position(3)
INTEGER, INTENT(IN)              :: SourceSize
!#if ((USE_HDG) && (PP_nVar==1))
!REAL, INTENT(IN)                 :: Fac(4:4)
!#else
REAL, INTENT(IN)                 :: Fac(4-SourceSize+1:4)
!#endif
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
LOGICAL                          :: firstElem,elemDone
INTEGER                          :: k, l, m
INTEGER                          :: kmin, kmax, lmin, lmax, mmin, mmax
INTEGER                          :: kk, ll, mm, ppp
INTEGER                          :: globElemID, CNElemID
INTEGER                          :: expo, nUsedElems, localElem
REAL                             :: radius2, S, S1
REAL                             :: totalCharge, alpha
REAL                             :: PartSourcetmp(1:4,0:PP_N,0:PP_N,0:PP_N)
#if USE_MPI
LOGICAL                          :: chargedone(1:nComputeNodeTotalElems)
#else
LOGICAL                          :: chargedone(1:nElems)
#endif /*USE_MPI*/
TYPE SPElem
  REAL, ALLOCATABLE     :: PartSourceLoc(:,:,:,:)
  INTEGER               :: globElemID
  TYPE (SPElem), POINTER :: next => null()
END TYPE
TYPE (SPElem), POINTER :: first => null()
TYPE (SPElem), POINTER :: element
!----------------------------------------------------------------------------------------------------------------------------------
chargedone(:) = .FALSE.
firstElem = .TRUE.

ALLOCATE(first)
ALLOCATE(first%PartSourceLoc(1:4,0:PP_N,0:PP_N,0:PP_N))
nUsedElems = 0
totalCharge = 0.0
!-- determine which background mesh cells (and interpolation points within) need to be considered
kmax = CEILING((Position(1)+r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1))
kmax = MIN(kmax,GEO%FIBGMimax)
kmin = FLOOR((Position(1)-r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1)+1)
kmin = MAX(kmin,GEO%FIBGMimin)
lmax = CEILING((Position(2)+r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2))
lmax = MIN(lmax,GEO%FIBGMjmax)
lmin = FLOOR((Position(2)-r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2)+1)
lmin = MAX(lmin,GEO%FIBGMjmin)
mmax = CEILING((Position(3)+r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3))
mmax = MIN(mmax,GEO%FIBGMkmax)
mmin = FLOOR((Position(3)-r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3)+1)
mmin = MAX(mmin,GEO%FIBGMkmin)
DO kk = kmin,kmax
  DO ll = lmin, lmax
    DO mm = mmin, mmax
      !--- go through all mapped elements not done yet
      DO ppp = 1,FIBGM_nElems(kk,ll,mm)
        globElemID = FIBGM_Element(FIBGM_offsetElem(kk,ll,mm)+ppp)
        elemDone = .FALSE.
        CNElemID = GetCNElemID(globElemID)
        localElem = globElemID-offSetElem
        IF (chargedone(CNElemID)) CYCLE
        IF (ABS(Position(dim_sf_dir)-ElemBaryNgeo(dim_sf_dir,CNElemID)).GT.(r_sf+ElemRadiusNGeo(CNElemID))) CYCLE
#if USE_LOADBALANCE
        IF ((localElem.GE.1).AND.localElem.LE.nElems) nDeposPerElem(localElem)=nDeposPerElem(localElem)+1
#endif /*USE_LOADBALANCE*/
          !--- go through all gauss points
        DO m=0,PP_N; DO l=0,PP_N; DO k=0,PP_N
          !-- calculate distance between gauss and particle
          radius2 = (Position(dim_sf_dir) - Elem_xGP_Shared(dim_sf_dir,k,l,m,globElemID))**2.
          !-- calculate charge and current density at ip point using a shape function
          !-- currently only one shapefunction available, more to follow (including structure change)
          IF (radius2 .LE. r2_sf) THEN
            IF (.NOT.elemDone) THEN
              PartSourcetmp = 0.0
              nUsedElems = nUsedElems + 1
              elemDone = .TRUE.
            END IF
            S = 1. - r2_sf_inv * radius2
            S1 = S*S
            DO expo = 3, alpha_sf
              S1 = S*S1
            END DO
            IF (SourceSize.EQ.1) THEN
              PartSourcetmp(4,k,l,m) = Fac(4) * S1
            ELSE
              PartSourcetmp(1:4,k,l,m) = Fac(1:4) * S1
            END IF
            totalCharge = totalCharge  + wGP(k)*wGP(l)*wGP(m)*PartSourcetmp(4,k,l,m)/ElemsJ(k,l,m,CNElemID)
          END IF
        END DO; END DO; END DO

        IF (elemDone) THEN
          IF (firstElem) THEN
            first%PartSourceLoc(:,:,:,:) = PartSourcetmp(:,:,:,:)
            first%globElemID = globElemID
            firstElem = .FALSE.
          ELSE
            ALLOCATE(element)
            ALLOCATE(element%PartSourceLoc(1:4,0:PP_N,0:PP_N,0:PP_N))
            element%next => first%next
            first%next => element
            element%PartSourceLoc(:,:,:,:) = PartSourcetmp(:,:,:,:)
            element%globElemID = globElemID
          END IF
        END IF
        chargedone(CNElemID) = .TRUE.
      END DO ! ppp
    END DO ! mm
  END DO ! ll
END DO ! kk

element => first
firstElem = .TRUE.
IF (nUsedElems.GT.0) THEN
  alpha = (Fac(4)/w_sf) / totalCharge
  DO ppp=1, nUsedElems
    globElemID = element%globElemID
    localElem = globElemID-offSetElem
    CNElemID = GetCNElemID(globElemID)
#if USE_MPI
    IF (((localElem).GE.1).AND.(localElem).LE.nElems) THEN
#endif /*USE_MPI*/
      IF (SourceSize.EQ.1) THEN
        PartSource(4,:,:,:, CNElemID) = PartSource(4,:,:,:, CNElemID) + alpha*element%PartSourceLoc(4,:,:,:)
      ELSE IF (SourceSize.EQ.4) THEN
        PartSource(1:4,:,:,:, CNElemID) = PartSource(1:4,:,:,:, CNElemID) + alpha*element%PartSourceLoc(1:4,:,:,:)
      END IF
#if USE_MPI
    ELSE
      IF (SourceSize.EQ.1) THEN
        PartSourceProc(4,:,:,:, SendElemShapeID(CNElemID)) =  &
            PartSourceProc(4,:,:,:, SendElemShapeID(CNElemID)) + alpha * element%PartSourceLoc(4,:,:,:)
      ELSE IF (SourceSize.EQ.4) THEN
        PartSourceProc(1:4,:,:,:, SendElemShapeID(CNElemID)) = &
            PartSourceProc(1:4,:,:,:, SendElemShapeID(CNElemID)) + alpha * element%PartSourceLoc(1:4,:,:,:)
      END IF
    END IF
#endif /*USE_MPI*/
    first => first%next
    DEALLOCATE(element%PartSourceLoc)
    DEALLOCATE(element)
    element => first
  END DO
END IF

END SUBROUTINE depoChargeOnDOFsSFChargeCon1D


SUBROUTINE depoChargeOnDOFsSFChargeCon2D(Position,SourceSize,Fac)
!============================================================================================================================
! actual deposition of single charge on DOFs via shapefunction
!============================================================================================================================
! use MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_PICDepo_Vars,           ONLY:r_sf, r2_sf, r2_sf_inv,alpha_sf,PartSource,w_sf,dim_sf_dir1,dim_sf_dir2
USE MOD_Mesh_Vars,              ONLY:nElems, offSetElem
USE MOD_Particle_Mesh_Vars,     ONLY:GEO, ElemBaryNgeo, FIBGM_offsetElem, FIBGM_nElems, FIBGM_Element, Elem_xGP_Shared
USE MOD_Particle_Mesh_Vars,     ONLY:ElemRadiusNGeo, ElemsJ
USE MOD_Preproc
USE MOD_Mesh_Tools,             ONLY:GetCNElemID
USE MOD_Interpolation_Vars,     ONLY:wGP
#if USE_MPI
USE MOD_MPI_Shared_Vars,        ONLY:nComputeNodeTotalElems
USE MOD_PICDepo_Vars,           ONLY:SendElemShapeID,PartSourceProc
#endif
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars,       ONLY:nDeposPerElem
#endif  /*USE_LOADBALANCE*/
!-----------------------------------------------------------------------------------------------------------------------------------
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                 :: Position(3)
INTEGER, INTENT(IN)              :: SourceSize
!#if ((USE_HDG) && (PP_nVar==1))
!REAL, INTENT(IN)                 :: Fac(4:4)
!#else
REAL, INTENT(IN)                 :: Fac(4-SourceSize+1:4)
!#endif
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
LOGICAL                          :: firstElem,elemDone
INTEGER                          :: k, l, m
INTEGER                          :: kmin, kmax, lmin, lmax, mmin, mmax
INTEGER                          :: kk, ll, mm, ppp
INTEGER                          :: globElemID, CNElemID
INTEGER                          :: expo, nUsedElems, localElem
REAL                             :: radius2, S, S1
REAL                             :: totalCharge, alpha
REAL                             :: PartSourcetmp(1:4,0:PP_N,0:PP_N,0:PP_N)
#if USE_MPI
LOGICAL                          :: chargedone(1:nComputeNodeTotalElems)
#else
LOGICAL                          :: chargedone(1:nElems)
#endif /*USE_MPI*/
TYPE SPElem
  REAL, ALLOCATABLE     :: PartSourceLoc(:,:,:,:)
  INTEGER               :: globElemID
  TYPE (SPElem), POINTER :: next => null()
END TYPE
TYPE (SPElem), POINTER :: first => null()
TYPE (SPElem), POINTER :: element
!----------------------------------------------------------------------------------------------------------------------------------
chargedone(:) = .FALSE.
firstElem = .TRUE.

ALLOCATE(first)
ALLOCATE(first%PartSourceLoc(1:4,0:PP_N,0:PP_N,0:PP_N))
nUsedElems = 0
totalCharge = 0.0
!-- determine which background mesh cells (and interpolation points within) need to be considered
kmax = CEILING((Position(1)+r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1))
kmax = MIN(kmax,GEO%FIBGMimax)
kmin = FLOOR((Position(1)-r_sf-GEO%xminglob)/GEO%FIBGMdeltas(1)+1)
kmin = MAX(kmin,GEO%FIBGMimin)
lmax = CEILING((Position(2)+r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2))
lmax = MIN(lmax,GEO%FIBGMjmax)
lmin = FLOOR((Position(2)-r_sf-GEO%yminglob)/GEO%FIBGMdeltas(2)+1)
lmin = MAX(lmin,GEO%FIBGMjmin)
mmax = CEILING((Position(3)+r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3))
mmax = MIN(mmax,GEO%FIBGMkmax)
mmin = FLOOR((Position(3)-r_sf-GEO%zminglob)/GEO%FIBGMdeltas(3)+1)
mmin = MAX(mmin,GEO%FIBGMkmin)
DO kk = kmin,kmax
  DO ll = lmin, lmax
    DO mm = mmin, mmax
      !--- go through all mapped elements not done yet
      DO ppp = 1,FIBGM_nElems(kk,ll,mm)
        globElemID = FIBGM_Element(FIBGM_offsetElem(kk,ll,mm)+ppp)
        elemDone = .FALSE.
        CNElemID = GetCNElemID(globElemID)
        localElem = globElemID-offSetElem
        IF (chargedone(CNElemID)) CYCLE
        ! Pick the opposite directions of dim_sf_dir in the 2D case via MERGE(...)
        IF (SQRT((Position(dim_sf_dir1)-ElemBaryNgeo(dim_sf_dir1,CNElemID))**2+&
                 (Position(dim_sf_dir2)-ElemBaryNgeo(dim_sf_dir2,CNElemID))**2).GT.(r_sf+ElemRadiusNGeo(CNElemID))) CYCLE
#if USE_LOADBALANCE
        IF ((localElem.GE.1).AND.localElem.LE.nElems) nDeposPerElem(localElem)=nDeposPerElem(localElem)+1
#endif /*USE_LOADBALANCE*/
          !--- go through all gauss points
        DO m=0,PP_N; DO l=0,PP_N; DO k=0,PP_N
          !-- calculate distance between gauss and particle
          ! Pick the opposite directions of dim_sf_dir in the 2D case via MERGE(...)
          radius2 = (Position(dim_sf_dir1) - Elem_xGP_Shared(dim_sf_dir1,k,l,m,globElemID))**2.+&
                    (Position(dim_sf_dir2) - Elem_xGP_Shared(dim_sf_dir2,k,l,m,globElemID))**2.
          !-- calculate charge and current density at ip point using a shape function
          !-- currently only one shapefunction available, more to follow (including structure change)
          IF (radius2 .LE. r2_sf) THEN
            IF (.NOT.elemDone) THEN
              PartSourcetmp = 0.0
              nUsedElems = nUsedElems + 1
              elemDone = .TRUE.
            END IF
            S = 1. - r2_sf_inv * radius2
            S1 = S*S
            DO expo = 3, alpha_sf
              S1 = S*S1
            END DO
            IF (SourceSize.EQ.1) THEN
              PartSourcetmp(4,k,l,m) = Fac(4) * S1
            ELSE
              PartSourcetmp(1:4,k,l,m) = Fac(1:4) * S1
            END IF
            totalCharge = totalCharge  + wGP(k)*wGP(l)*wGP(m)*PartSourcetmp(4,k,l,m)/ElemsJ(k,l,m,CNElemID)
          END IF
        END DO; END DO; END DO

        IF (elemDone) THEN
          IF (firstElem) THEN
            first%PartSourceLoc(:,:,:,:) = PartSourcetmp(:,:,:,:)
            first%globElemID = globElemID
            firstElem = .FALSE.
          ELSE
            ALLOCATE(element)
            ALLOCATE(element%PartSourceLoc(1:4,0:PP_N,0:PP_N,0:PP_N))
            element%next => first%next
            first%next => element
            element%PartSourceLoc(:,:,:,:) = PartSourcetmp(:,:,:,:)
            element%globElemID = globElemID
          END IF
        END IF
        chargedone(CNElemID) = .TRUE.
      END DO ! ppp
    END DO ! mm
  END DO ! ll
END DO ! kk

element => first
firstElem = .TRUE.
IF (nUsedElems.GT.0) THEN
  alpha = (Fac(4)/w_sf) / totalCharge
  DO ppp=1, nUsedElems
    globElemID = element%globElemID
    localElem = globElemID-offSetElem
    CNElemID = GetCNElemID(globElemID)
#if USE_MPI
    IF (((localElem).GE.1).AND.(localElem).LE.nElems) THEN
#endif /*USE_MPI*/
      IF (SourceSize.EQ.1) THEN
        PartSource(4,:,:,:, CNElemID) = PartSource(4,:,:,:, CNElemID) + alpha*element%PartSourceLoc(4,:,:,:)
      ELSE IF (SourceSize.EQ.4) THEN
        PartSource(1:4,:,:,:, CNElemID) = PartSource(1:4,:,:,:, CNElemID) + alpha*element%PartSourceLoc(1:4,:,:,:)
      END IF
#if USE_MPI
    ELSE
      IF (SourceSize.EQ.1) THEN
        PartSourceProc(4,:,:,:, SendElemShapeID(CNElemID)) =  &
            PartSourceProc(4,:,:,:, SendElemShapeID(CNElemID)) + alpha * element%PartSourceLoc(4,:,:,:)
      ELSE IF (SourceSize.EQ.4) THEN
        PartSourceProc(1:4,:,:,:, SendElemShapeID(CNElemID)) = &
            PartSourceProc(1:4,:,:,:, SendElemShapeID(CNElemID)) + alpha * element%PartSourceLoc(1:4,:,:,:)
      END IF
    END IF
#endif /*USE_MPI*/
    first => first%next
    DEALLOCATE(element%PartSourceLoc)
    DEALLOCATE(element)
    element => first
  END DO
END IF

END SUBROUTINE depoChargeOnDOFsSFChargeCon2D


SUBROUTINE depoChargeOnDOFsSFAdaptive(Position,SourceSize,Fac,PartIdx)
!============================================================================================================================
! actual deposition of single charge on DOFs via shapefunction
!============================================================================================================================
! use MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_PICDepo_Vars,           ONLY:alpha_sf,PartSource,w_sf,SFElemr2_Shared
USE MOD_Mesh_Vars,              ONLY:nElems, offSetElem
USE MOD_Particle_Mesh_Vars,     ONLY:ElemBaryNgeo, Elem_xGP_Shared
USE MOD_Particle_Mesh_Vars,     ONLY:ElemRadiusNGeo, ElemsJ, ElemToElemMapping,ElemToElemInfo
USE MOD_Preproc
USE MOD_Mesh_Tools,             ONLY:GetCNElemID, GetGlobalElemID
USE MOD_Interpolation_Vars,     ONLY:wGP
USE MOD_Particle_Vars,          ONLY:PEM
#if USE_MPI
USE MOD_MPI_Shared_Vars,        ONLY:nComputeNodeTotalElems
USE MOD_PICDepo_Vars,           ONLY:SendElemShapeID,PartSourceProc
#endif
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars,       ONLY:nDeposPerElem
#endif  /*USE_LOADBALANCE*/
!-----------------------------------------------------------------------------------------------------------------------------------
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                 :: Position(3)
INTEGER, INTENT(IN)              :: SourceSize
INTEGER, INTENT(IN)              :: PartIdx
!#if ((USE_HDG) && (PP_nVar==1))
!REAL, INTENT(IN)                 :: Fac(4:4)
!#else
REAL, INTENT(IN)                 :: Fac(4-SourceSize+1:4)
!#endif
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
LOGICAL                          :: firstElem,elemDone
INTEGER                          :: k, l, m
INTEGER                          :: ppp
INTEGER                          :: globElemID, CNElemID, OrigCNElemID, OrigElem
INTEGER                          :: expo, nUsedElems, localElem
REAL                             :: radius2, S, S1
REAL                             :: totalCharge, alpha
REAL                             :: PartSourcetmp(1:4,0:PP_N,0:PP_N,0:PP_N)
#if USE_MPI
LOGICAL                          :: chargedone(1:nComputeNodeTotalElems)
#else
LOGICAL                          :: chargedone(1:nElems)
#endif /*USE_MPI*/
TYPE SPElem
  REAL, ALLOCATABLE     :: PartSourceLoc(:,:,:,:)
  INTEGER               :: globElemID
  TYPE (SPElem), POINTER :: next => null()
END TYPE
TYPE (SPElem), POINTER :: first => null()
TYPE (SPElem), POINTER :: element
!----------------------------------------------------------------------------------------------------------------------------------
chargedone(:) = .FALSE.
firstElem = .TRUE.

ALLOCATE(first)
ALLOCATE(first%PartSourceLoc(1:4,0:PP_N,0:PP_N,0:PP_N))
nUsedElems = 0
totalCharge = 0.0
!-- determine which background mesh cells (and interpolation points within) need to be considered
!--- go through all mapped elements not done yet
OrigElem = PEM%GlobalElemID(PartIdx)
OrigCNElemID = GetCNElemID(OrigElem)
DO ppp = 0,ElemToElemMapping(2,OrigCNElemID)  
  IF (ppp.EQ.0) THEN
    globElemID = OrigElem
  ELSE    
    globElemID = GetGlobalElemID(ElemToElemInfo(ElemToElemMapping(1,OrigCNElemID)+ppp))
  END IF 
  elemDone = .FALSE.
  CNElemID = GetCNElemID(globElemID)
  localElem = globElemID-offSetElem
  IF (chargedone(CNElemID)) CYCLE
  IF (VECNORM(Position(1:3)-ElemBaryNgeo(1:3,CNElemID)).GT.(SFElemr2_Shared(1,CNElemID)+ElemRadiusNGeo(CNElemID))) CYCLE
#if USE_LOADBALANCE
  IF ((localElem.GE.1).AND.localElem.LE.nElems) nDeposPerElem(localElem)=nDeposPerElem(localElem)+1
#endif /*USE_LOADBALANCE*/
    !--- go through all gauss points
  DO m=0,PP_N; DO l=0,PP_N; DO k=0,PP_N
    !-- calculate distance between gauss and particle
    radius2 = SUM((Position(1:3) - Elem_xGP_Shared(1:3,k,l,m,globElemID))**2.)
    !-- calculate charge and current density at ip point using a shape function
    !-- currently only one shapefunction available, more to follow (including structure change)
    IF (radius2 .LE. SFElemr2_Shared(2,CNElemID)) THEN
      IF (.NOT.elemDone) THEN
        PartSourcetmp = 0.0
        nUsedElems = nUsedElems + 1
        elemDone = .TRUE.
      END IF
      S = 1. - radius2/SFElemr2_Shared(2,CNElemID)
      S1 = S*S
      DO expo = 3, alpha_sf
        S1 = S*S1
      END DO
      IF (SourceSize.EQ.1) THEN
        PartSourcetmp(4,k,l,m) = Fac(4) * S1
      ELSE
        PartSourcetmp(1:4,k,l,m) = Fac(1:4) * S1
      END IF
      totalCharge = totalCharge  + wGP(k)*wGP(l)*wGP(m)*PartSourcetmp(4,k,l,m)/ElemsJ(k,l,m,CNElemID)
    END IF
  END DO; END DO; END DO

  IF (elemDone) THEN
    IF (firstElem) THEN
      first%PartSourceLoc(:,:,:,:) = PartSourcetmp(:,:,:,:)
      first%globElemID = globElemID
      firstElem = .FALSE.
    ELSE
      ALLOCATE(element)
      ALLOCATE(element%PartSourceLoc(1:4,0:PP_N,0:PP_N,0:PP_N))
      element%next => first%next
      first%next => element
      element%PartSourceLoc(:,:,:,:) = PartSourcetmp(:,:,:,:)
      element%globElemID = globElemID
    END IF
  END IF
  chargedone(CNElemID) = .TRUE.
END DO ! ppp

element => first
firstElem = .TRUE.
IF (nUsedElems.GT.0) THEN
  alpha = (Fac(4)/w_sf) / totalCharge
  DO ppp=1, nUsedElems
    globElemID = element%globElemID
    localElem = globElemID-offSetElem
    CNElemID = GetCNElemID(globElemID)
#if USE_MPI
    IF (((localElem).GE.1).AND.(localElem).LE.nElems) THEN
#endif /*USE_MPI*/
      IF (SourceSize.EQ.1) THEN
        PartSource(4,:,:,:, CNElemID) = PartSource(4,:,:,:, CNElemID) + alpha*element%PartSourceLoc(4,:,:,:)
      ELSE IF (SourceSize.EQ.4) THEN
        PartSource(1:4,:,:,:, CNElemID) = PartSource(1:4,:,:,:, CNElemID) + alpha*element%PartSourceLoc(1:4,:,:,:)
      END IF
#if USE_MPI
    ELSE
      IF (SourceSize.EQ.1) THEN
        PartSourceProc(4,:,:,:, SendElemShapeID(CNElemID)) =  &
            PartSourceProc(4,:,:,:, SendElemShapeID(CNElemID)) + alpha * element%PartSourceLoc(4,:,:,:)
      ELSE IF (SourceSize.EQ.4) THEN
        PartSourceProc(1:4,:,:,:, SendElemShapeID(CNElemID)) = &
            PartSourceProc(1:4,:,:,:, SendElemShapeID(CNElemID)) + alpha * element%PartSourceLoc(1:4,:,:,:)
      END IF
    END IF
#endif /*USE_MPI*/
    first => first%next
    DEALLOCATE(element%PartSourceLoc)
    DEALLOCATE(element)
    element => first
  END DO
END IF

END SUBROUTINE depoChargeOnDOFsSFAdaptive


SUBROUTINE depoChargeOnDOFsSFAdaptive1D(Position,SourceSize,Fac,PartIdx)
!============================================================================================================================
! actual deposition of single charge on DOFs via shapefunction
!============================================================================================================================
! use MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_PICDepo_Vars,           ONLY:alpha_sf,PartSource,w_sf,SFElemr2_Shared,dim_sf_dir
USE MOD_Mesh_Vars,              ONLY:nElems, offSetElem
USE MOD_Particle_Mesh_Vars,     ONLY:ElemBaryNgeo, Elem_xGP_Shared
USE MOD_Particle_Mesh_Vars,     ONLY:ElemRadiusNGeo, ElemsJ, ElemToElemMapping,ElemToElemInfo
USE MOD_Preproc
USE MOD_Mesh_Tools,             ONLY:GetCNElemID, GetGlobalElemID
USE MOD_Interpolation_Vars,     ONLY:wGP
USE MOD_Particle_Vars,          ONLY:PEM
#if USE_MPI
USE MOD_MPI_Shared_Vars,        ONLY:nComputeNodeTotalElems
USE MOD_PICDepo_Vars,           ONLY:SendElemShapeID,PartSourceProc
#endif
#if USE_LOADBALANCE
USE MOD_LoadBalance_Vars,       ONLY:nDeposPerElem
#endif  /*USE_LOADBALANCE*/
!-----------------------------------------------------------------------------------------------------------------------------------
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL, INTENT(IN)                 :: Position(3)
INTEGER, INTENT(IN)              :: SourceSize
INTEGER, INTENT(IN)              :: PartIdx
!#if ((USE_HDG) && (PP_nVar==1))
!REAL, INTENT(IN)                 :: Fac(4:4)
!#else
REAL, INTENT(IN)                 :: Fac(4-SourceSize+1:4)
!#endif
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
LOGICAL                          :: firstElem,elemDone
INTEGER                          :: k, l, m
INTEGER                          :: ppp
INTEGER                          :: globElemID, CNElemID, OrigCNElemID, OrigElem
INTEGER                          :: expo, nUsedElems, localElem
REAL                             :: radius2, S, S1
REAL                             :: totalCharge, alpha
REAL                             :: PartSourcetmp(1:4,0:PP_N,0:PP_N,0:PP_N)
#if USE_MPI
LOGICAL                          :: chargedone(1:nComputeNodeTotalElems)
#else
LOGICAL                          :: chargedone(1:nElems)
#endif /*USE_MPI*/
TYPE SPElem
  REAL, ALLOCATABLE     :: PartSourceLoc(:,:,:,:)
  INTEGER               :: globElemID
  TYPE (SPElem), POINTER :: next => null()
END TYPE
TYPE (SPElem), POINTER :: first => null()
TYPE (SPElem), POINTER :: element
!----------------------------------------------------------------------------------------------------------------------------------
chargedone(:) = .FALSE.
firstElem = .TRUE.

ALLOCATE(first)
ALLOCATE(first%PartSourceLoc(1:4,0:PP_N,0:PP_N,0:PP_N))
nUsedElems = 0
totalCharge = 0.0
!-- determine which background mesh cells (and interpolation points within) need to be considered
!--- go through all mapped elements not done yet
OrigElem = PEM%GlobalElemID(PartIdx)
OrigCNElemID = GetCNElemID(OrigElem)
DO ppp = 0,ElemToElemMapping(2,OrigCNElemID)  
  IF (ppp.EQ.0) THEN
    globElemID = OrigElem
  ELSE    
    globElemID = GetGlobalElemID(ElemToElemInfo(ElemToElemMapping(1,OrigCNElemID)+ppp))
  END IF 
  elemDone = .FALSE.
  CNElemID = GetCNElemID(globElemID)
  localElem = globElemID-offSetElem
  IF (chargedone(CNElemID)) CYCLE
  IF (ABS(Position(dim_sf_dir)-ElemBaryNgeo(dim_sf_dir,CNElemID)).GT.(SFElemr2_Shared(1,CNElemID)+ElemRadiusNGeo(CNElemID))) CYCLE
#if USE_LOADBALANCE
  IF ((localElem.GE.1).AND.localElem.LE.nElems) nDeposPerElem(localElem)=nDeposPerElem(localElem)+1
#endif /*USE_LOADBALANCE*/
    !--- go through all gauss points
  DO m=0,PP_N; DO l=0,PP_N; DO k=0,PP_N
    !-- calculate distance between gauss and particle
    radius2 = (Position(dim_sf_dir) - Elem_xGP_Shared(dim_sf_dir,k,l,m,globElemID))**2.
    !-- calculate charge and current density at ip point using a shape function
    !-- currently only one shapefunction available, more to follow (including structure change)
    IF (radius2 .LE. SFElemr2_Shared(2,CNElemID)) THEN
      IF (.NOT.elemDone) THEN
        PartSourcetmp = 0.0
        nUsedElems = nUsedElems + 1
        elemDone = .TRUE.
      END IF
      S = 1. - radius2/SFElemr2_Shared(2,CNElemID)
      S1 = S*S
      DO expo = 3, alpha_sf
        S1 = S*S1
      END DO
      IF (SourceSize.EQ.1) THEN
        PartSourcetmp(4,k,l,m) = Fac(4) * S1
      ELSE
        PartSourcetmp(1:4,k,l,m) = Fac(1:4) * S1
      END IF
      totalCharge = totalCharge  + wGP(k)*wGP(l)*wGP(m)*PartSourcetmp(4,k,l,m)/ElemsJ(k,l,m,CNElemID)
    END IF
  END DO; END DO; END DO

  IF (elemDone) THEN
    IF (firstElem) THEN
      first%PartSourceLoc(:,:,:,:) = PartSourcetmp(:,:,:,:)
      first%globElemID = globElemID
      firstElem = .FALSE.
    ELSE
      ALLOCATE(element)
      ALLOCATE(element%PartSourceLoc(1:4,0:PP_N,0:PP_N,0:PP_N))
      element%next => first%next
      first%next => element
      element%PartSourceLoc(:,:,:,:) = PartSourcetmp(:,:,:,:)
      element%globElemID = globElemID
    END IF
  END IF
  chargedone(CNElemID) = .TRUE.
END DO ! ppp

element => first
firstElem = .TRUE.
IF (nUsedElems.GT.0) THEN
  alpha = (Fac(4)/w_sf) / totalCharge
  DO ppp=1, nUsedElems
    globElemID = element%globElemID
    localElem = globElemID-offSetElem
    CNElemID = GetCNElemID(globElemID)
#if USE_MPI
    IF (((localElem).GE.1).AND.(localElem).LE.nElems) THEN
#endif /*USE_MPI*/
      IF (SourceSize.EQ.1) THEN
        PartSource(4,:,:,:, CNElemID) = PartSource(4,:,:,:, CNElemID) + alpha*element%PartSourceLoc(4,:,:,:)
      ELSE IF (SourceSize.EQ.4) THEN
        PartSource(1:4,:,:,:, CNElemID) = PartSource(1:4,:,:,:, CNElemID) + alpha*element%PartSourceLoc(1:4,:,:,:)
      END IF
#if USE_MPI
    ELSE
      IF (SourceSize.EQ.1) THEN
        PartSourceProc(4,:,:,:, SendElemShapeID(CNElemID)) =  &
            PartSourceProc(4,:,:,:, SendElemShapeID(CNElemID)) + alpha * element%PartSourceLoc(4,:,:,:)
      ELSE IF (SourceSize.EQ.4) THEN
        PartSourceProc(1:4,:,:,:, SendElemShapeID(CNElemID)) = &
            PartSourceProc(1:4,:,:,:, SendElemShapeID(CNElemID)) + alpha * element%PartSourceLoc(1:4,:,:,:)
      END IF
    END IF
#endif /*USE_MPI*/
    first => first%next
    DEALLOCATE(element%PartSourceLoc)
    DEALLOCATE(element)
    element => first
  END DO
END IF

END SUBROUTINE depoChargeOnDOFsSFAdaptive1D


END MODULE MOD_PICDepo_Shapefunction_Tools
