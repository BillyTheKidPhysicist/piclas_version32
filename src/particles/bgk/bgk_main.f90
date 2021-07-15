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

MODULE MOD_BGK
!===================================================================================================================================
!> Main module for the the Bhatnagar-Gross-Krook method
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE

INTERFACE BGK_main
  MODULE PROCEDURE BGK_main
END INTERFACE

!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
PUBLIC :: BGK_main, BGK_DSMC_main
!===================================================================================================================================

CONTAINS

SUBROUTINE BGK_DSMC_main()
!===================================================================================================================================
!> Coupled BGK and DSMC routine: Cell-local decision with BGKDSMCSwitchDens
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_BGK_Adaptation      ,ONLY: BGK_octree_adapt, BGK_quadtree_adapt
USE MOD_Particle_Vars       ,ONLY: PEM, Species, WriteMacroVolumeValues, Symmetry, usevMPF
USE MOD_BGK_Vars            ,ONLY: DoBGKCellAdaptation,BGKDSMCSwitchDens
! USE MOD_BGK_Vars            ,ONLY: BGKMovingAverage,ElemNodeAveraging,BGKMovingAverageLength
USE MOD_BGK_Vars            ,ONLY: BGK_MeanRelaxFactor,BGK_MeanRelaxFactorCounter,BGK_MaxRelaxFactor,BGK_QualityFacSamp
USE MOD_BGK_Vars            ,ONLY: BGK_MaxRotRelaxFactor, BGK_PrandtlNumber, BGK_ExpectedPrandtlNumber
USE MOD_BGK_CollOperator    ,ONLY: BGK_CollisionOperator
USE MOD_DSMC                ,ONLY: DSMC_main
USE MOD_DSMC_Vars           ,ONLY: DSMC_RHS, DSMC, RadialWeighting
USE MOD_Mesh_Vars           ,ONLY: nElems, offsetElem
USE MOD_Part_Tools          ,ONLY: GetParticleWeight
USE MOD_TimeDisc_Vars       ,ONLY: TEnd, Time
USE MOD_Particle_Mesh_Vars  ,ONLY: ElemVolume_Shared
USE MOD_Mesh_Tools          ,ONLY: GetCNElemID
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: iElem, nPart, iLoop, iPart, CNElemID
INTEGER, ALLOCATABLE  :: iPartIndx_Node(:)
LOGICAL               :: DoElement(nElems)
REAL                  :: dens, partWeight, totalWeight
!===================================================================================================================================
DSMC_RHS = 0.0
DoElement = .FALSE.

DO iElem = 1, nElems
  nPart = PEM%pNumber(iElem)
  CNElemID = GetCNElemID(iElem + offsetElem)
  IF ((nPart.EQ.0).OR.(nPart.EQ.1)) CYCLE

  totalWeight = 0.0
  iPart = PEM%pStart(iElem)
  DO iLoop = 1, nPart
    partWeight = GetParticleWeight(iPart)
    totalWeight = totalWeight + partWeight
    iPart = PEM%pNext(iPart)
  END DO

  IF(usevMPF.OR.RadialWeighting%DoRadialWeighting) THEN
    dens = totalWeight / ElemVolume_Shared(CNElemID)
  ELSE
    dens = totalWeight * Species(1)%MacroParticleFactor / ElemVolume_Shared(CNElemID)
  END IF

  IF (dens.LT.BGKDSMCSwitchDens) THEN
    DoElement(iElem) = .TRUE.
    CYCLE
  END IF

  IF (DoBGKCellAdaptation) THEN
    IF(Symmetry%Order.EQ.2) THEN
      CALL BGK_quadtree_adapt(iElem)
    ELSE
      CALL BGK_octree_adapt(iElem)
    END IF
  ELSE
    ALLOCATE(iPartIndx_Node(nPart))
    iPart = PEM%pStart(iElem)
    DO iLoop = 1, nPart
      iPartIndx_Node(iLoop) = iPart
      iPart = PEM%pNext(iPart)
    END DO

    IF(DSMC%CalcQualityFactors) THEN
      BGK_MeanRelaxFactorCounter = 0; BGK_MeanRelaxFactor = 0.; BGK_MaxRelaxFactor = 0.; BGK_MaxRotRelaxFactor = 0.
      BGK_PrandtlNumber=0.; BGK_ExpectedPrandtlNumber=0.
    END IF
    ! IF (BGKMovingAverage) THEN
    !   CALL BGK_CollisionOperator(iPartIndx_Node, nPart, ElemVolume_Shared(CNElemID), &
    !       ElemNodeAveraging(iElem)%Root%AverageValues(1:5,1:BGKMovingAverageLength), &
    !            CorrectStep = ElemNodeAveraging(iElem)%Root%CorrectStep)
    ! ELSE
      CALL BGK_CollisionOperator(iPartIndx_Node, nPart, ElemVolume_Shared(CNElemID))
    ! END IF
    DEALLOCATE(iPartIndx_Node)
    IF(DSMC%CalcQualityFactors) THEN
      IF((Time.GE.(1-DSMC%TimeFracSamp)*TEnd).OR.WriteMacroVolumeValues) THEN
        BGK_QualityFacSamp(1,iElem) = BGK_QualityFacSamp(1,iElem) + BGK_MeanRelaxFactor
        BGK_QualityFacSamp(2,iElem) = BGK_QualityFacSamp(2,iElem) + REAL(BGK_MeanRelaxFactorCounter)
        BGK_QualityFacSamp(3,iElem) = BGK_QualityFacSamp(3,iElem) + BGK_MaxRelaxFactor
        BGK_QualityFacSamp(4,iElem) = BGK_QualityFacSamp(4,iElem) + 1.
        BGK_QualityFacSamp(5,iElem) = BGK_QualityFacSamp(5,iElem) + BGK_MaxRotRelaxFactor
        BGK_QualityFacSamp(6,iElem) = BGK_QualityFacSamp(6,iElem) + BGK_PrandtlNumber
        BGK_QualityFacSamp(7,iElem) = BGK_QualityFacSamp(7,iElem) + BGK_ExpectedPrandtlNumber
      END IF
    END IF
  END IF
END DO

CALL DSMC_main(DoElement)

END SUBROUTINE BGK_DSMC_main


SUBROUTINE BGK_main()
!===================================================================================================================================
!> Main routine for the BGK model
!> 1.) Loop over all elements, call of octree refinement or directly of the collision operator
!> 2.) Sampling of macroscopic variables with DSMC routines
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_TimeDisc_Vars       ,ONLY: TEnd, Time
USE MOD_Mesh_Vars           ,ONLY: nElems, offsetElem
USE MOD_BGK_Adaptation      ,ONLY: BGK_octree_adapt, BGK_quadtree_adapt
USE MOD_Particle_Vars       ,ONLY: PEM, WriteMacroVolumeValues, WriteMacroSurfaceValues, Symmetry
USE MOD_BGK_Vars            ,ONLY: DoBGKCellAdaptation!, BGKMovingAverage, ElemNodeAveraging, BGKMovingAverageLength
USE MOD_BGK_Vars            ,ONLY: BGK_MeanRelaxFactor,BGK_MeanRelaxFactorCounter,BGK_MaxRelaxFactor,BGK_QualityFacSamp
USE MOD_BGK_Vars            ,ONLY: BGK_MaxRotRelaxFactor, BGK_PrandtlNumber, BGK_ExpectedPrandtlNumber
USE MOD_BGK_CollOperator    ,ONLY: BGK_CollisionOperator
USE MOD_DSMC_Analyze        ,ONLY: DSMCMacroSampling
USE MOD_Particle_Mesh_Vars  ,ONLY: ElemVolume_Shared
USE MOD_DSMC_Vars           ,ONLY: DSMC_RHS, DSMC
USE MOD_Mesh_Tools          ,ONLY: GetCNElemID
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: iElem, nPart, iLoop, iPart, CNElemID
INTEGER, ALLOCATABLE  :: iPartIndx_Node(:)
!===================================================================================================================================
DSMC_RHS = 0.0

IF (DoBGKCellAdaptation) THEN
  DO iElem = 1, nElems
    IF(Symmetry%Order.EQ.2) THEN
      CALL BGK_quadtree_adapt(iElem)
    ELSE
      CALL BGK_octree_adapt(iElem)
    END IF
  END DO
ELSE ! No octree cell refinement
  DO iElem = 1, nElems
    CNElemID = GetCNElemID(iElem + offsetElem)
    nPart = PEM%pNumber(iElem)
    IF ((nPart.EQ.0).OR.(nPart.EQ.1)) CYCLE
    ALLOCATE(iPartIndx_Node(nPart))
    iPart = PEM%pStart(iElem)
    DO iLoop = 1, nPart
      iPartIndx_Node(iLoop) = iPart
      iPart = PEM%pNext(iPart)
    END DO

    IF(DSMC%CalcQualityFactors) THEN
      BGK_MeanRelaxFactorCounter = 0; BGK_MeanRelaxFactor = 0.; BGK_MaxRelaxFactor = 0.; BGK_MaxRotRelaxFactor = 0.
      BGK_PrandtlNumber=0.; BGK_ExpectedPrandtlNumber=0.
    END IF

    ! IF (BGKMovingAverage) THEN
    !   CALL BGK_CollisionOperator(iPartIndx_Node, nPart, ElemVolume_Shared(CNElemID), &
    !       ElemNodeAveraging(iElem)%Root%AverageValues(1:5,1:BGKMovingAverageLength), &
    !            CorrectStep = ElemNodeAveraging(iElem)%Root%CorrectStep)
    ! ELSE
      CALL BGK_CollisionOperator(iPartIndx_Node, nPart, ElemVolume_Shared(CNElemID))
    ! END IF
    DEALLOCATE(iPartIndx_Node)
    IF(DSMC%CalcQualityFactors) THEN
      IF((Time.GE.(1-DSMC%TimeFracSamp)*TEnd).OR.WriteMacroVolumeValues) THEN
        BGK_QualityFacSamp(1,iElem) = BGK_QualityFacSamp(1,iElem) + BGK_MeanRelaxFactor
        BGK_QualityFacSamp(2,iElem) = BGK_QualityFacSamp(2,iElem) + REAL(BGK_MeanRelaxFactorCounter)
        BGK_QualityFacSamp(3,iElem) = BGK_QualityFacSamp(3,iElem) + BGK_MaxRelaxFactor
        BGK_QualityFacSamp(4,iElem) = BGK_QualityFacSamp(4,iElem) + 1.
        BGK_QualityFacSamp(5,iElem) = BGK_QualityFacSamp(5,iElem) + BGK_MaxRotRelaxFactor
        BGK_QualityFacSamp(6,iElem) = BGK_QualityFacSamp(6,iElem) + BGK_PrandtlNumber
        BGK_QualityFacSamp(7,iElem) = BGK_QualityFacSamp(7,iElem) + BGK_ExpectedPrandtlNumber
      END IF
    END IF
  END DO
END IF ! DoBGKCellAdaptation

! Sampling of macroscopic values
! (here for a continuous average; average over N iterations is performed in src/analyze/analyze.f90)
IF (.NOT.WriteMacroVolumeValues .AND. .NOT.WriteMacroSurfaceValues) THEN
  CALL DSMCMacroSampling()
END IF

END SUBROUTINE BGK_main

END MODULE MOD_BGK