MODULE MOD_LD
!===================================================================================================================================
! module including low diffusion model
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

PUBLIC :: LD_main, LD_reposition, LD_PerfectReflection, LD_SetParticlePosition
!===================================================================================================================================

CONTAINS


SUBROUTINE LD_main()

USE MOD_LD_Vars
USE MOD_Mesh_Vars,             ONLY : nElems, nSides
USE MOD_Particle_Vars,         ONLY : PDM, Time, WriteMacroValues, PEM, PartState
USE MOD_LD_mean_cell,          ONLY : CalcMacCellLDValues
USE MOD_LD_lag_velo,           ONLY : CalcSurfLagVelo
USE MOD_LD_reassign_part_prop, ONLY : LD_reassign_prop
USE MOD_LD_part_treat,         ONLY : LDPartTreament
USE MOD_TimeDisc_Vars,         ONLY : TEnd
USE MOD_DSMC_Vars,             ONLY : DSMC
USE MOD_LD_Analyze

!--------------------------------------------------------------------------------------------------!
! main DSMC routine
!--------------------------------------------------------------------------------------------------!
   IMPLICIT NONE                                                                                   !
!--------------------------------------------------------------------------------------------------!
! argument list declaration                                                                        !
! Local variable declaration                                                                       !
  INTEGER           :: iElem
  INTEGER           :: nOutput
!--------------------------------------------------------------------------------------------------!
  LD_RHS(1:PDM%ParticleVecLength,1) = 0.0
  LD_RHS(1:PDM%ParticleVecLength,2) = 0.0
  LD_RHS(1:PDM%ParticleVecLength,3) = 0.0
  IsDoneLagVelo(1:nSides) = .FALSE.
  CALL CalcMacCellLDValues
  CALL CalcSurfLagVelo
  IF(LD_RepositionFak.NE. 0) THEN
    CALL LD_reposition()
  END IF
  DO iElem = 1, nElems
    IF (PEM%pNumber(iElem).GT. 1) THEN
      CALL LD_reassign_prop(iElem)
      CALL LDPartTreament(iElem)
    END IF
  END DO
  IF (.NOT.WriteMacroValues) THEN
    IF(Time.ge.(1-DSMC%TimeFracSamp)*TEnd) THEN
      CALL LD_data_sampling()  ! Data sampling for output
      IF(DSMC%NumOutput.NE.0) THEN
        nOutput = (DSMC%TimeFracSamp * TEnd)/DSMC%DeltaTimeOutput-DSMC%NumOutput + 1
        IF(Time.ge.((1-DSMC%TimeFracSamp)*TEnd + DSMC%DeltaTimeOutput * nOutput)) THEN
          DSMC%NumOutput = DSMC%NumOutput - 1
          CALL LD_output_calc(nOutput)
        END IF
      END IF
    END IF
  END IF

END SUBROUTINE LD_main

!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!
!                          _   _     _   _   _   _   _
!                         / \ / \   / \ / \ / \ / \ / \ 
!                        ( L | D ) ( T | O | O | L | S )
!                         \_/ \_/   \_/ \_/ \_/ \_/ \_/ 
!--------------------------------------------------------------------------------------------------!
SUBROUTINE LD_reposition
!--------------------------------------------------------------------------------------------------!
  USE MOD_Particle_Vars,         ONLY : PartState, PEM, GEO
  USE MOD_Mesh_Vars,             ONLY : nElems
  USE MOD_part_MPFtools,         ONLY : MapToGeo
  USE MOD_LD_Vars,               ONLY : LD_RepositionFak
  IMPLICIT NONE                                                                                    !
!--------------------------------------------------------------------------------------------------!
INTEGER               :: iElem
INTEGER               :: iPart, iNode,iPartIndx,nPart
REAL                  :: RandVac(3), iRan, P(3,8)
!--------------------------------------------------------------------------------------------------!

  DO iElem = 1, nElems
    nPart     = PEM%pNumber(iElem)
    iPartIndx = PEM%pStart(iElem)
    DO iNode = 1,8
      P(1:3,iNode) = GEO%NodeCoords(1:3,GEO%ElemToNodeID(iNode,iElem))
    END DO
    DO iPart = 1, nPart
      CALL RANDOM_NUMBER(iRan)
      IF (iRan.LT. LD_RepositionFak) THEN     
        CALL RANDOM_NUMBER(RandVac)
        RandVac = RandVac * 2.0 - 1.0
        PartState(iPartIndx, 1:3) = MapToGeo(RandVac, P)
        iPartIndx = PEM%pNext(iPartIndx)
      END IF
    END DO
  END DO

END SUBROUTINE LD_reposition

!--------------------------------------------------------------------------------------------------!

!--------------------------------------------------------------------------------------------------!

SUBROUTINE LD_PerfectReflection(nx,ny,nz,xNod,yNod,zNod,PoldStarX,PoldStarY,PoldStarZ,i)
!--------------------------------------------------------------------------------------------------!
  USE MOD_LD_Vars
  USE MOD_Particle_Vars,         ONLY : lastPartPos
  USE MOD_TimeDisc_Vars,         ONLY : dt
  IMPLICIT NONE                                                                                    !
!--------------------------------------------------------------------------------------------------!
! Local variable declaration                                                                       !
   REAL                             :: PnewX, PnewY, PnewZ, nVal                                   !
   REAL                             :: bx,by,bz, ax,ay,az, dist                                    !
   REAL                             :: PnewStarX, PnewStarY, PnewStarZ, Velo                       !
   REAL                             :: VelX, VelY, VelZ, NewVelocity                               !
!--------------------------------------------------------------------------------------------------!
! INPUT VARIABLES
!--------------------------------------------------------------------------------------------------!
  INTEGER, INTENT(IN)           :: i
  REAL, INTENT(IN)             :: nx,ny,nz,xNod,yNod,zNod,PoldStarX,PoldStarY,PoldStarZ
!--------------------------------------------------------------------------------------------------!

   PnewX = lastPartPos(i,1) + PartStateBulkValues(i,1) * dt
   PnewY = lastPartPos(i,2) + PartStateBulkValues(i,2) * dt
   PnewZ = lastPartPos(i,3) + PartStateBulkValues(i,3) * dt

   bx = PnewX - xNod
   by = PnewY - yNod
   bz = PnewZ - zNod

   ax = bx - nx * (bx * nx + by * ny + bz * nz)
   ay = by - ny * (bx * nx + by * ny + bz * nz)
   az = bz - nz * (bx * nx + by * ny + bz * nz)

   dist = SQRT(((ay * bz - az * by) * (ay * bz - az * by) +   &
        (az * bx - ax * bz) * (az * bx - ax * bz) +   &
        (ax * by - ay * bx) * (ax * by - ay * bx))/   &
        (ax * ax + ay * ay + az * az))

!   If vector from old point to new point goes through the node, a will be zero
!   dist is then simply length of vector b instead of |axb|/|a|
   IF (dist.NE.dist) dist = SQRT(bx*bx+by*by+bz*bz)

   PnewStarX = PnewX - 2 * dist * nx
   PnewStarY = PnewY - 2 * dist * ny
   PnewStarZ = PnewZ - 2 * dist * nz

   !---- Calculate new velocity vector

   Velo = SQRT(PartStateBulkValues(i,1) * PartStateBulkValues(i,1) + &
               PartStateBulkValues(i,2) * PartStateBulkValues(i,2) + &
               PartStateBulkValues(i,3) * PartStateBulkValues(i,3))

   VelX = PnewStarX - PoldStarX
   VelY = PnewStarY - PoldStarY
   VelZ = PnewStarZ - PoldStarZ

   NewVelocity = SQRT(VelX * VelX + VelY * VelY + VelZ * VelZ)

   VelX = VelX/NewVelocity * Velo
   VelY = VelY/NewVelocity * Velo
   VelZ = VelZ/NewVelocity * Velo

   !---- Assign new values to "old" variables to continue loop

   PartStateBulkValues(i,1)   = VelX 
   PartStateBulkValues(i,2)   = VelY
   PartStateBulkValues(i,3)   = VelZ

END SUBROUTINE LD_PerfectReflection

!--------------------------------------------------------------------------------------------------!

!--------------------------------------------------------------------------------------------------!

SUBROUTINE LD_SetParticlePosition(chunkSize,particle_positions_Temp)
!--------------------------------------------------------------------------------------------------!
  USE MOD_Particle_Vars,         ONLY : GEO
  USE MOD_Mesh_Vars,             ONLY : nElems
  USE MOD_part_MPFtools,         ONLY : MapToGeo
  IMPLICIT NONE                                                                                    !
!--------------------------------------------------------------------------------------------------!
INTEGER, INTENT(INOUT)           :: chunkSize
REAL,ALLOCATABLE, INTENT(OUT)    :: particle_positions_Temp(:)
!--------------------------------------------------------------------------------------------------!
! Local variable declaration                                                                       !
!--------------------------------------------------------------------------------------------------!
INTEGER               :: iElem, ichunkSize
INTEGER               :: iPart, iNode, nPart
REAL                  :: RandVac(3), iRan, P(3,8),RandomPos(3)
REAL                  :: PartDens, GlobalVol, FractNbr
!--------------------------------------------------------------------------------------------------!

  ALLOCATE(particle_positions_Temp(6*chunkSize))
  DO iElem = 1, nElems
    GlobalVol = GlobalVol + GEO%Volume(iElem)
  END DO
  PartDens = chunkSize / GlobalVol
  ichunkSize = 1
  DO iElem = 1, nElems
    FractNbr = PartDens * GEO%Volume(iElem) - AINT(PartDens * GEO%Volume(iElem))
    CALL RANDOM_NUMBER(iRan)
    IF (iRan .GT. FractNbr) THEN
      nPart = AINT(PartDens * GEO%Volume(iElem))
    ELSE
      nPart = AINT(PartDens * GEO%Volume(iElem)) + 1
    END IF
    DO iNode = 1,8
      P(1:3,iNode) = GEO%NodeCoords(1:3,GEO%ElemToNodeID(iNode,iElem))
    END DO
    DO iPart = 1, nPart   
      CALL RANDOM_NUMBER(RandVac)
      RandVac = RandVac * 2.0 - 1.0
      RandomPos(1:3) = MapToGeo(RandVac, P)
      particle_positions_Temp(ichunkSize*3-2) = RandomPos(1)
      particle_positions_Temp(ichunkSize*3-1) = RandomPos(2)
      particle_positions_Temp(ichunkSize*3)   = RandomPos(3)
      ichunkSize = ichunkSize + 1
    END DO
  END DO
  chunkSize = ichunkSize

END SUBROUTINE LD_SetParticlePosition
!--------------------------------------------------------------------------------------------------!

END MODULE MOD_LD