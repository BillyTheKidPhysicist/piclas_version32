#include "boltzplatz.h"

MODULE MOD_LD_Init
!===================================================================================================================================
! Initialisation of LD variables!
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
INTERFACE InitLD
  MODULE PROCEDURE InitLD
END INTERFACE
INTERFACE CalcDegreeOfFreedom
  MODULE PROCEDURE CalcDegreeOfFreedom
END INTERFACE

PUBLIC :: InitLD, CalcDegreeOfFreedom
!===================================================================================================================================

CONTAINS

SUBROUTINE InitLD()
!===================================================================================================================================
! Init of DSMC Vars
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_LD_Vars
USE MOD_Mesh_Vars,             ONLY : nElems, nSides, SideToElem, ElemToSide, Elem_xGP
!USE MOD_Mesh_Vars,             ONLY : nNodes    !!! nur für "Tetra-Methode"
USE MOD_Particle_Vars,         ONLY : GEO, PDM, Species, PartSpecies, nSpecies
USE nr,                        ONLY : gaussj 
USE MOD_DSMC_Init,             ONLY : InitDSMC
USE MOD_DSMC_Vars,             ONLY : SpecDSMC, CollisMode
USE MOD_ReadInTools
USE MOD_part_MPFtools,         ONLY : MapToGeo
#ifdef MPI
USE MOD_Mesh_Vars,             ONLY : nInnerSides, nBCSides
USE MOD_MPI_Vars
USE MOD_part_MPI_Vars,         ONLY : MPIGEO 
#endif
! IMPLICIT VARIABLE HANDLING
 IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                 :: iElem, trinum, iLocSide, iNode, iPart, iInit, iSpec, SideID, Elem2
REAL                    :: NVecTest
REAL,ALLOCATABLE       :: CellCenterList(:,:)
REAL                    :: CellNodePos(3,8)
REAL                    :: OriginCube(3), CellCenterLocal(3)
#ifdef MPI
REAL                    :: MPICellNodePos(3,8)
REAL                    :: MPICellCenterLocal(3)
INTEGER                 :: Element, MPINodeNum, MPINodeID, haloSideID, SumOfMPISides, EndOfMPINeighbor, iProc, OffsetInnerAndBCSides
#endif
CHARACTER(32)           :: hilf
!===================================================================================================================================

  SWRITE(UNIT_StdOut,'(132("-"))')
  SWRITE(UNIT_stdOut,'(A)') ' LD INIT ...'

  LD_SecantMeth%Guess = GETREAL('LD-InitialGuess','10')
  LD_SecantMeth%MaxIter = GETINT('LD-MaxIterNumForLagVelo','100')
  LD_SecantMeth%Accuracy = GETREAL('LD-AccuracyForLagVelo','0.001')
  LD_RepositionFak = GETREAL('LD-RepositionsFaktor','0.0')
  LD_RelaxationFak = GETREAL('LD-RelaxationsFaktor','0.0')
  LD_DSMC_RelaxationFak_BufferA = GETREAL('LD-DSMC-RelaxationsFaktorForBufferA','0.0')
  LD_CalcDelta_t=GETLOGICAL('LD-CFL-CalcDelta-t','.FALSE.')
  LD_CalcResidual=GETLOGICAL('LD_CalcResidual','.FALSE.')

  ALLOCATE(LD_Residual(nElems,6))
  LD_Residual(1:nElems,1) = 0.0
  LD_Residual(1:nElems,2) = 0.0
  LD_Residual(1:nElems,3) = 0.0
  LD_Residual(1:nElems,4) = 0.0
  LD_Residual(1:nElems,5) = 0.0
  LD_Residual(1:nElems,6) = 0.0

  ALLOCATE(TempDens(nElems))

  ALLOCATE(BulkValues(nElems))
  BulkValues(1:nElems)%CellV(1)        = 0.0
  BulkValues(1:nElems)%CellV(2)        = 0.0
  BulkValues(1:nElems)%CellV(3)        = 0.0
  BulkValues(1:nElems)%DegreeOfFreedom = 0.0 
  BulkValues(1:nElems)%Beta            = 0.0  
  BulkValues(1:nElems)%MassDens        = 0.0
  BulkValues(1:nElems)%BulkTemperature = 0.0
  BulkValues(1:nElems)%DynamicVisc     = 0.0
  BulkValues(1:nElems)%ThermalCond     = 0.0

  ALLOCATE(BulkValuesOpenBC(nElems))
  BulkValuesOpenBC(1:nElems)%CellV(1)        = 0.0
  BulkValuesOpenBC(1:nElems)%CellV(2)        = 0.0
  BulkValuesOpenBC(1:nElems)%CellV(3)        = 0.0
  BulkValuesOpenBC(1:nElems)%DegreeOfFreedom = 0.0 
  BulkValuesOpenBC(1:nElems)%Beta            = 0.0  
  BulkValuesOpenBC(1:nElems)%MassDens        = 0.0
  BulkValuesOpenBC(1:nElems)%DynamicVisc     = 0.0
  BulkValuesOpenBC(1:nElems)%ThermalCond     = 0.0

  ALLOCATE(SurfLagValues(6,nElems,2))
  SurfLagValues(1:6,1:nElems,1:2)%LagVelo    = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%DeltaM(1)  = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%DeltaM(2)  = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%DeltaM(3)  = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%DeltaE     = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%LagNormVec(1) = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%LagNormVec(2) = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%LagNormVec(3) = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%LagTangVec(1,1) = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%LagTangVec(1,2) = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%LagTangVec(1,3) = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%LagTangVec(2,1) = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%LagTangVec(2,2) = 0.0
  SurfLagValues(1:6,1:nElems,1:2)%LagTangVec(2,3) = 0.0

  ALLOCATE(MeanSurfValues(6,nElems))
  MeanSurfValues(1:6,1:nElems)%MeanLagVelo     = 0.0
  MeanSurfValues(1:6,1:nElems)%MeanBaseD       = 0.0
  MeanSurfValues(1:6,1:nElems)%MeanBaseD2      = 0.0
  MeanSurfValues(1:6,1:nElems)%MeanNormVec(1)  = 0.0
  MeanSurfValues(1:6,1:nElems)%MeanNormVec(2)  = 0.0
  MeanSurfValues(1:6,1:nElems)%MeanNormVec(3)  = 0.0
  MeanSurfValues(1:6,1:nElems)%MeanBulkVelo(1) = 0.0
  MeanSurfValues(1:6,1:nElems)%MeanBulkVelo(2) = 0.0
  MeanSurfValues(1:6,1:nElems)%MeanBulkVelo(3) = 0.0
  MeanSurfValues(1:6,1:nElems)%CellCentDist(1) = 0.0
  MeanSurfValues(1:6,1:nElems)%CellCentDist(2) = 0.0
  MeanSurfValues(1:6,1:nElems)%CellCentDist(3) = 0.0

!!!!  ALLOCATE(NewNodePosIndx(1:3,nNodes))  !!! nur für "Tetra-Methode"

!--- calculate cellcenter distance for viscousity terms
  ALLOCATE(CellCenterList(3,nElems))
  DO iElem=1, nElems
    DO iNode=1, 8
      CellNodePos(1,iNode) = GEO%NodeCoords(1,GEO%ElemToNodeID(iNode,iElem))
      CellNodePos(2,iNode) = GEO%NodeCoords(2,GEO%ElemToNodeID(iNode,iElem))
      CellNodePos(3,iNode) = GEO%NodeCoords(3,GEO%ElemToNodeID(iNode,iElem))
    END DO
    OriginCube(1:3) = 0.0
    CellCenterLocal = MapToGeo(OriginCube,CellNodePos)
    CellCenterList(1,iElem) = CellCenterLocal(1)
    CellCenterList(2,iElem) = CellCenterLocal(2)
    CellCenterList(3,iElem) = CellCenterLocal(3)
  END DO
!--- end calculate cellcenter distance for viscousity terms

  ALLOCATE(IsDoneLagVelo(nSides))
  IsDoneLagVelo(1:nSides)   = .FALSE.
  DO iElem=1, nElems
    DO iLocSide = 1, 6
      DO trinum=1, 2
        SurfLagValues(iLocSide, iElem, trinum)%Area = CalcTriNumArea(iLocSide, iElem, trinum)
        CALL CalcLagNormVec(iLocSide, iElem, trinum)
        NVecTest = (GEO%NodeCoords(1,GEO%ElemSideNodeID(1,iLocSide,iElem))-Elem_xGP(1,0,0,0,iElem)) &
                 * SurfLagValues(iLocSide, iElem,trinum)%LagNormVec(1) &
                 + (GEO%NodeCoords(2,GEO%ElemSideNodeID(1,iLocSide,iElem))-Elem_xGP(2,0,0,0,iElem)) &
                 * SurfLagValues(iLocSide, iElem,trinum)%LagNormVec(2) &
                 + (GEO%NodeCoords(3,GEO%ElemSideNodeID(1,iLocSide,iElem))-Elem_xGP(3,0,0,0,iElem)) &
                 * SurfLagValues(iLocSide, iElem,trinum)%LagNormVec(3)
        IF (NVecTest.LE.0.0) THEN
          SWRITE(UNIT_StdOut,'(132("-"))')
          SWRITE(UNIT_StdOut,'(A)') 'Element:',iElem
          CALL abort(__STAMP__,&
               'ERROR in Calculation of NormVec for Element')
        END IF  
!--- calculate cellcenter distance for viscousity terms
        SideID = ElemToSide(1,iLocSide,iElem)
#ifdef MPI
        IF (SideID.GT.nBCSides+nInnerSides) THEN ! it must be a MPI Side
          haloSideID = MPIGEO%haloMPINbSide(SideID-nInnerSides-nBCSides)
          IF (MPIGEO%SideToElem(S2E_ELEM_ID,haloSideID).NE.-1) THEN
           Element = MPIGEO%SideToElem(S2E_ELEM_ID,haloSideID)
          ELSE
           Element = MPIGEO%SideToElem(S2E_NB_ELEM_ID,haloSideID)
          END IF
          iNode = 1
          DO MPINodeNum = 1,4
            MPINodeID = MPIGEO%ElemSideNodeID(MPINodeNum,1,Element)
            MPICellNodePos(1,iNode) = MPIGEO%NodeCoords(1,MPINodeID)
            MPICellNodePos(2,iNode) = MPIGEO%NodeCoords(2,MPINodeID)
            MPICellNodePos(3,iNode) = MPIGEO%NodeCoords(3,MPINodeID)
            iNode = iNode + 1
          END DO
          DO MPINodeNum = 1,4
            MPINodeID = MPIGEO%ElemSideNodeID(MPINodeNum,6,Element)
            MPICellNodePos(1,iNode) = MPIGEO%NodeCoords(1,MPINodeID)
            MPICellNodePos(2,iNode) = MPIGEO%NodeCoords(2,MPINodeID)
            MPICellNodePos(3,iNode) = MPIGEO%NodeCoords(3,MPINodeID)
            iNode = iNode + 1
          END DO
          OriginCube(1:3) = 0.0
          MPICellCenterLocal = MapToGeo(OriginCube,MPICellNodePos)
          MeanSurfValues(iLocSide, iElem)%CellCentDist(1) = CellCenterList(1,iElem) - MPICellCenterLocal(1)
          MeanSurfValues(iLocSide, iElem)%CellCentDist(2) = CellCenterList(2,iElem) - MPICellCenterLocal(2)
          MeanSurfValues(iLocSide, iElem)%CellCentDist(3) = CellCenterList(3,iElem) - MPICellCenterLocal(3)
        ELSE
#endif
          IF (SideToElem(1,SideID) .EQ. iElem) THEN
            IF (SideToElem(2,SideID) .GT. 0) THEN ! it must be an interior face
              IF (SideToElem(1,SideID).NE.SideToElem(2,SideID)) THEN ! no one periodic cell
                Elem2 = SideToElem(2,SideID)
                  MeanSurfValues(iLocSide, iElem)%CellCentDist(1) = CellCenterList(1,iElem) - CellCenterList(1,Elem2)
                  MeanSurfValues(iLocSide, iElem)%CellCentDist(2) = CellCenterList(2,iElem) - CellCenterList(2,Elem2)
                  MeanSurfValues(iLocSide, iElem)%CellCentDist(3) = CellCenterList(3,iElem) - CellCenterList(3,Elem2)
              END IF
            END IF
          ELSE
            IF (SideToElem(1,SideID) .GT. 0) THEN ! it must be an interior face
              IF (SideToElem(1,SideID).NE.SideToElem(2,SideID)) THEN ! no one periodic cell
                Elem2 = SideToElem(1,SideID)
                MeanSurfValues(iLocSide, iElem)%CellCentDist(1) = CellCenterList(1,iElem) - CellCenterList(1,Elem2)
                MeanSurfValues(iLocSide, iElem)%CellCentDist(2) = CellCenterList(2,iElem) - CellCenterList(2,Elem2)
                MeanSurfValues(iLocSide, iElem)%CellCentDist(3) = CellCenterList(3,iElem) - CellCenterList(3,Elem2)
              END IF
            END IF
          END IF
#ifdef MPI
        END IF
#endif
!--- end calculate cellcenter distance for viscousity terms  
      END DO
      CALL SetMeanSurfValues(iLocSide, iElem)
      NVecTest = (GEO%NodeCoords(1,GEO%ElemSideNodeID(1,iLocSide,iElem))-Elem_xGP(1,0,0,0,iElem)) &  
               * MeanSurfValues(iLocSide, iElem)%MeanNormVec(1) &
               + (GEO%NodeCoords(2,GEO%ElemSideNodeID(1,iLocSide,iElem))-Elem_xGP(2,0,0,0,iElem)) &
               * MeanSurfValues(iLocSide, iElem)%MeanNormVec(2) &
               + (GEO%NodeCoords(3,GEO%ElemSideNodeID(1,iLocSide,iElem))-Elem_xGP(3,0,0,0,iElem)) & 
               * MeanSurfValues(iLocSide, iElem)%MeanNormVec(3)
      IF (NVecTest.LE.0.0) THEN
        SWRITE(UNIT_StdOut,'(132("-"))')
        SWRITE(UNIT_StdOut,'(A)') 'Element:',iElem
        CALL abort(__STAMP__,&
             'ERROR in Calculation of NormVec for Element')
      END IF
    END DO
  END DO
  DEALLOCATE(CellCenterList)
  ALLOCATE(PartStateBulkValues(PDM%maxParticleNumber,5))
  ALLOCATE(LD_RHS(PDM%maxParticleNumber,3))
  LD_RHS = 0.0
  ALLOCATE(LD_DSMC_RHS(PDM%maxParticleNumber,3))
  LD_DSMC_RHS = 0.0

! Set Particle Bulk Values
  DO iSpec = 1, nSpecies
    IF(SpecDSMC(iSpec)%InterID.EQ.2) THEN
      IF (.NOT.((CollisMode.EQ.2).OR.(CollisMode.EQ.3))) THEN
        WRITE(UNIT=hilf,FMT='(I2)') iSpec
        SpecDSMC(iSpec)%CharaTVib  = GETREAL('Part-Species'//TRIM(hilf)//'-CharaTempVib','0.')  
        SpecDSMC(iSpec)%Ediss_eV   = GETREAL('Part-Species'//TRIM(hilf)//'-Ediss_eV','0.')
      END IF
    END IF
  END DO

  DO iPart = 1, PDM%maxParticleNumber
    IF (PDM%ParticleInside(ipart)) THEN
      iInit = PDM%PartInit(iPart)
      PartStateBulkValues(iPart,1) = Species(PartSpecies(iPart))%Init(iInit)%VeloVecIC(1) &
                                   * Species(PartSpecies(iPart))%Init(iInit)%VeloIC
      PartStateBulkValues(iPart,2) = Species(PartSpecies(iPart))%Init(iInit)%VeloVecIC(2) &
                                   * Species(PartSpecies(iPart))%Init(iInit)%VeloIC
      PartStateBulkValues(iPart,3) = Species(PartSpecies(iPart))%Init(iInit)%VeloVecIC(3) &
                                   * Species(PartSpecies(iPart))%Init(iInit)%VeloIC
      PartStateBulkValues(iPart,4) = Species(PartSpecies(iPart))%Init(iInit)%MWTemperatureIC
      PartStateBulkValues(iPart,5) = CalcDegreeOfFreedom(iPart)
    END IF
  END DO

#ifdef MPI
  SumOfMPISides = 0
  DO iProc =1, nNbProcs
    SumOfMPISides =SumOfMPISides + nMPISides_MINE_Proc(iProc) + nMPISides_YOUR_Proc(iProc)
  END DO
  OffsetInnerAndBCSides = OffsetMPISides_MINE(0) + 1
  EndOfMPINeighbor = OffsetInnerAndBCSides + SumOfMPISides - 1
  ALLOCATE(MPINeighborBulkVal(OffsetInnerAndBCSides:EndOfMPINeighbor,1:8))
#endif

  SWRITE(UNIT_stdOut,'(A)')' INIT LD DONE!'
  SWRITE(UNIT_StdOut,'(132("-"))')

  DEALLOCATE(PDM%PartInit)  ! normaly done in DSMC_ini.f90

END SUBROUTINE InitLD

!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!

REAL FUNCTION CalcDegreeOfFreedom(iPart)
!===================================================================================================================================
! calculation of degree of freedom per part
!===================================================================================================================================
! MODULES
  USE MOD_LD_Vars
  USE MOD_DSMC_Vars,          ONLY : SpecDSMC, CollisMode, PartStateIntEn, DSMC
  USE MOD_Particle_Vars,      ONLY : Species, PartSpecies, BoltzmannConst
  USE MOD_DSMC_Analyze,       ONLY : CalcTVib
!--------------------------------------------------------------------------------------------------!
! perform chemical init
!--------------------------------------------------------------------------------------------------!
   IMPLICIT NONE 
! LOCAL VARIABLES
!--------------------------------------------------------------------------------------------------!
  REAL                          :: ZetaRot, ZetaVib, TvibToTemp, JToEv
!  REAL                          :: ModTvibToTemp, PartTvib
  INTEGER                       :: iSpec
!--------------------------------------------------------------------------------------------------!
! INPUT VARIABLES
!--------------------------------------------------------------------------------------------------!
  INTEGER, INTENT(IN)           :: iPart
!#ifdef MPI
!#endif
!===================================================================================================
  JToEv = 1.602176565E-19
  iSpec = PartSpecies(iPart)
  IF(SpecDSMC(iSpec)%InterID.EQ.2) THEN
    ZetaRot = 2.0
    IF (CollisMode.NE.1) THEN
!!!!!!!!      PartTvib = CalcTVib(SpecDSMC(iSpec)%CharaTVib, PartStateIntEn(iPart,1), SpecDSMC(iSpec)%MaxVibQuant)

!!!!!!!      PartTvib = SpecDSMC(iSpec)%CharaTVib / LOG(1 + 1/(PartStateIntEn(iPart,1) & 
!!!!!!!               / (BoltzmannConst * SpecDSMC(iSpec)%CharaTVib)-DSMC%GammaQuant))

      TvibToTemp = PartStateIntEn(iPart,1)/(BoltzmannConst*SpecDSMC(iSpec)%CharaTVib)
      IF (TvibToTemp.LE.DSMC%GammaQuant) THEN
        TvibToTemp = 0.0    
        ZetaVib = 0.0     
      ELSE
        TvibToTemp = SpecDSMC(iSpec)%CharaTVib/LOG(1 + 1/(TvibToTemp-DSMC%GammaQuant))
!!!!!!!      ModTvibToTemp = SpecDSMC(iSpec)%Ediss_eV * JToEv / (BoltzmannConst * PartTvib)
        ZetaVib = 2.0 * SpecDSMC(iSpec)%CharaTVib/TvibToTemp / (EXP(SpecDSMC(iSpec)%CharaTVib/TvibToTemp)-1)
      END IF
    ELSE
      ZetaVib = 0.0
    END IF
  ELSE
    ZetaRot = 0.0
    ZetaVib = 0.0
  END IF
  CalcDegreeOfFreedom = 3.0 + ZetaRot + ZetaVib

END FUNCTION CalcDegreeOfFreedom

!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!

REAL FUNCTION CalcTriNumArea(iLocSide, Element, trinum)
!===================================================================================================================================
! Calculation of triangle surface area
!===================================================================================================================================
! MODULES
  USE MOD_Particle_Vars,          ONLY : GEO
!--------------------------------------------------------------------------------------------------!
   IMPLICIT NONE                                                                                   !
!--------------------------------------------------------------------------------------------------!
! argument list declaration                                                                        !
! Local variable declaration                                                                       !
  INTEGER                     :: Nod2, Nod3
  REAL                        :: xNod1, xNod2, xNod3 
  REAL                        :: yNod1, yNod2, yNod3 
  REAL                        :: zNod1, zNod2, zNod3 
  REAL                        :: Vector1(1:3), Vector2(1:3)
!--------------------------------------------------------------------------------------------------!
! INPUT VARIABLES
  INTEGER, INTENT(IN)         :: iLocSide, Element, trinum
!--------------------------------------------------------------------------------------------------!

!--- Node 1 ---
   xNod1 = GEO%NodeCoords(1,GEO%ElemSideNodeID(1,iLocSide,Element))
   yNod1 = GEO%NodeCoords(2,GEO%ElemSideNodeID(1,iLocSide,Element))
   zNod1 = GEO%NodeCoords(3,GEO%ElemSideNodeID(1,iLocSide,Element))

!--- Node 2 ---
   Nod2 = trinum + 1      ! vector 1-2 for first triangle
                          ! vector 1-3 for second triangle
   xNod2 = GEO%NodeCoords(1,GEO%ElemSideNodeID(Nod2,iLocSide,Element))
   yNod2 = GEO%NodeCoords(2,GEO%ElemSideNodeID(Nod2,iLocSide,Element))
   zNod2 = GEO%NodeCoords(3,GEO%ElemSideNodeID(Nod2,iLocSide,Element))

!--- Node 3 ---
   Nod3 = trinum + 2      ! vector 1-3 for first triangle
                          ! vector 1-4 for second triangle
   xNod3 = GEO%NodeCoords(1,GEO%ElemSideNodeID(Nod3,iLocSide,Element))
   yNod3 = GEO%NodeCoords(2,GEO%ElemSideNodeID(Nod3,iLocSide,Element))
   zNod3 = GEO%NodeCoords(3,GEO%ElemSideNodeID(Nod3,iLocSide,Element))

   Vector1(1) = xNod2 - xNod1
   Vector1(2) = yNod2 - yNod1
   Vector1(3) = zNod2 - zNod1

   Vector2(1) = xNod3 - xNod1
   Vector2(2) = yNod3 - yNod1
   Vector2(3) = zNod3 - zNod1

!--- 2 * Area = |cross product| of vector 1-2 and 1-3 for first triangle or
                                 ! vector 1-3 and 1-4 for second triangle
   CalcTriNumArea = 0.5*SQRT((Vector1(2)*Vector2(3)-Vector1(3)*Vector2(2))**2 &
           + (-Vector1(1)*Vector2(3)+Vector1(3)*Vector2(1))**2 &
           + (Vector1(1)*Vector2(2)-Vector1(2)*Vector2(1))**2)

  RETURN

END FUNCTION CalcTriNumArea

!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!

SUBROUTINE CalcLagNormVec(iLocSide, Element, trinum)
!===================================================================================================================================
! Calculation of normal vector
!===================================================================================================================================
! MODULES
  USE MOD_LD_Vars
  USE MOD_Particle_Vars,          ONLY : GEO
!--------------------------------------------------------------------------------------------------!
   IMPLICIT NONE                                                                                   !
!--------------------------------------------------------------------------------------------------!
! argument list declaration                                                                        !
! Local variable declaration                                                                       !
  INTEGER                     :: Nod2, Nod3
  REAL                        :: xNod1, xNod2, xNod3 
  REAL                        :: yNod1, yNod2, yNod3 
  REAL                        :: zNod1, zNod2, zNod3 
  REAL                        :: Vector1(1:3), Vector2(1:3)
  REAL                        :: nx, ny, nz, nVal
!--------------------------------------------------------------------------------------------------!
! INPUT VARIABLES
  INTEGER, INTENT(IN)         :: iLocSide, Element, trinum
!--------------------------------------------------------------------------------------------------!
!--- Node 1 ---
   xNod1 = GEO%NodeCoords(1,GEO%ElemSideNodeID(1,iLocSide,Element))
   yNod1 = GEO%NodeCoords(2,GEO%ElemSideNodeID(1,iLocSide,Element))
   zNod1 = GEO%NodeCoords(3,GEO%ElemSideNodeID(1,iLocSide,Element))

!--- Node 2 ---
   Nod2 = trinum + 1      ! vector 1-2 for first triangle
                          ! vector 1-3 for second triangle
   xNod2 = GEO%NodeCoords(1,GEO%ElemSideNodeID(Nod2,iLocSide,Element))
   yNod2 = GEO%NodeCoords(2,GEO%ElemSideNodeID(Nod2,iLocSide,Element))
   zNod2 = GEO%NodeCoords(3,GEO%ElemSideNodeID(Nod2,iLocSide,Element))

!--- Node 3 ---
   Nod3 = trinum + 2      ! vector 1-3 for first triangle
                          ! vector 1-4 for second triangle
   xNod3 = GEO%NodeCoords(1,GEO%ElemSideNodeID(Nod3,iLocSide,Element))
   yNod3 = GEO%NodeCoords(2,GEO%ElemSideNodeID(Nod3,iLocSide,Element))
   zNod3 = GEO%NodeCoords(3,GEO%ElemSideNodeID(Nod3,iLocSide,Element))

   Vector1(1) = xNod2 - xNod1
   Vector1(2) = yNod2 - yNod1
   Vector1(3) = zNod2 - zNod1

   Vector2(1) = xNod3 - xNod1
   Vector2(2) = yNod3 - yNod1
   Vector2(3) = zNod3 - zNod1

   nx = Vector1(2) * Vector2(3) - Vector1(3) * Vector2(2) ! n is inward normal vector
   ny = Vector1(3) * Vector2(1) - Vector1(1) * Vector2(3)
   nz = Vector1(1) * Vector2(2) - Vector1(2) * Vector2(1)

   nVal = SQRT(nx*nx + ny*ny + nz*nz)

   SurfLagValues(iLocSide, Element,trinum)%LagNormVec(1) = nx/nVal
   SurfLagValues(iLocSide, Element,trinum)%LagNormVec(2) = ny/nVal
   SurfLagValues(iLocSide, Element,trinum)%LagNormVec(3) = nz/nVal

   nVal = SQRT( Vector1(1)*Vector1(1) + Vector1(2)*Vector1(2) + Vector1(3)*Vector1(3) )
!--- first tangential Vector == Node1->Node2
   SurfLagValues(iLocSide, Element,trinum)%LagTangVec(1,1) = Vector1(1)/nVal
   SurfLagValues(iLocSide, Element,trinum)%LagTangVec(1,2) = Vector1(2)/nVal
   SurfLagValues(iLocSide, Element,trinum)%LagTangVec(1,3) = Vector1(3)/nVal
!--- second tangential Vector == |cross product| of N_Vec and Tang_1
   SurfLagValues(iLocSide, Element,trinum)%LagTangVec(2,1) = &
          SurfLagValues(iLocSide, Element,trinum)%LagNormVec(2) * SurfLagValues(iLocSide, Element,trinum)%LagTangVec(1,3) &
        - SurfLagValues(iLocSide, Element,trinum)%LagNormVec(3) * SurfLagValues(iLocSide, Element,trinum)%LagTangVec(1,2)
   SurfLagValues(iLocSide, Element,trinum)%LagTangVec(2,2) = &
        - SurfLagValues(iLocSide, Element,trinum)%LagNormVec(1) * SurfLagValues(iLocSide, Element,trinum)%LagTangVec(1,3) &
        + SurfLagValues(iLocSide, Element,trinum)%LagNormVec(3) * SurfLagValues(iLocSide, Element,trinum)%LagTangVec(1,1)
   SurfLagValues(iLocSide, Element,trinum)%LagTangVec(2,3) = &
          SurfLagValues(iLocSide, Element,trinum)%LagNormVec(1) * SurfLagValues(iLocSide, Element,trinum)%LagTangVec(1,2) &
        - SurfLagValues(iLocSide, Element,trinum)%LagNormVec(2) * SurfLagValues(iLocSide, Element,trinum)%LagTangVec(1,1)
END SUBROUTINE CalcLagNormVec
!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!
SUBROUTINE SetMeanSurfValues(iLocSide, Element)
!===================================================================================================================================
! Definition of surface fit
!===================================================================================================================================
! MODULES
  USE MOD_LD_Vars
  USE MOD_Particle_Vars,          ONLY : GEO
!--------------------------------------------------------------------------------------------------!
   IMPLICIT NONE                                                                                   !
!--------------------------------------------------------------------------------------------------!
! argument list declaration                                                                        !
! Local variable declaration  
  REAL                        :: xNod1, xNod2, xNod3, xNod4
  REAL                        :: yNod1, yNod2, yNod3, yNod4 
  REAL                        :: zNod1, zNod2, zNod3, zNod4 
  REAL                        :: Vector1(3), Vector2(3),BaseVectorS(3) 
  REAL                        :: nx, ny, nz, nVal
!--------------------------------------------------------------------------------------------------!
! INPUT VARIABLES
  INTEGER, INTENT(IN)         :: iLocSide, Element                                                 !
!--------------------------------------------------------------------------------------------------!

  !--- Node 1 ---
  xNod1 = GEO%NodeCoords(1,GEO%ElemSideNodeID(1,iLocSide,Element))
  yNod1 = GEO%NodeCoords(2,GEO%ElemSideNodeID(1,iLocSide,Element))
  zNod1 = GEO%NodeCoords(3,GEO%ElemSideNodeID(1,iLocSide,Element))
  !--- Node 2 ---
  xNod2 = GEO%NodeCoords(1,GEO%ElemSideNodeID(2,iLocSide,Element))
  yNod2 = GEO%NodeCoords(2,GEO%ElemSideNodeID(2,iLocSide,Element))
  zNod2 = GEO%NodeCoords(3,GEO%ElemSideNodeID(2,iLocSide,Element))
  !--- Node 3 ---
  xNod3 = GEO%NodeCoords(1,GEO%ElemSideNodeID(3,iLocSide,Element))
  yNod3 = GEO%NodeCoords(2,GEO%ElemSideNodeID(3,iLocSide,Element))
  zNod3 = GEO%NodeCoords(3,GEO%ElemSideNodeID(3,iLocSide,Element))
  !--- Node 4 ---
  xNod4 = GEO%NodeCoords(1,GEO%ElemSideNodeID(4,iLocSide,Element))
  yNod4 = GEO%NodeCoords(2,GEO%ElemSideNodeID(4,iLocSide,Element))
  zNod4 = GEO%NodeCoords(3,GEO%ElemSideNodeID(4,iLocSide,Element))
  Vector1(1) = xNod3 - xNod1
  Vector1(2) = yNod3 - yNod1
  Vector1(3) = zNod3 - zNod1
  Vector2(1) = xNod4 - xNod2
  Vector2(2) = yNod4 - yNod2
  Vector2(3) = zNod4 - zNod2
  nx = Vector1(2) * Vector2(3) - Vector1(3) * Vector2(2) ! n is inward normal vector
  ny = Vector1(3) * Vector2(1) - Vector1(1) * Vector2(3)
  nz = Vector1(1) * Vector2(2) - Vector1(2) * Vector2(1)
  BaseVectorS(1:3) = 0.25 *( &
                   + GEO%NodeCoords(1:3,GEO%ElemSideNodeID(1,iLocSide,Element)) &
                   + GEO%NodeCoords(1:3,GEO%ElemSideNodeID(2,iLocSide,Element)) &
                   + GEO%NodeCoords(1:3,GEO%ElemSideNodeID(3,iLocSide,Element)) &
                   + GEO%NodeCoords(1:3,GEO%ElemSideNodeID(4,iLocSide,Element)) )
  nVal = SQRT(nx*nx + ny*ny + nz*nz)
  MeanSurfValues(iLocSide, Element)%MeanNormVec(1) = nx/nVal
  MeanSurfValues(iLocSide, Element)%MeanNormVec(2) = ny/nVal
  MeanSurfValues(iLocSide, Element)%MeanNormVec(3) = nz/nVal
  MeanSurfValues(iLocSide, Element)%MeanBaseD = MeanSurfValues(iLocSide, Element)%MeanNormVec(1) * BaseVectorS(1) &
                                  + MeanSurfValues(iLocSide, Element)%MeanNormVec(2) * BaseVectorS(2) &
                                  + MeanSurfValues(iLocSide, Element)%MeanNormVec(3) * BaseVectorS(3)

END SUBROUTINE SetMeanSurfValues

!--------------------------------------------------------------------------------------------------!
!--------------------------------------------------------------------------------------------------!

END MODULE MOD_LD_Init
