MODULE MOD_Analyze_Vars
!===================================================================================================================================
! Contains global variables used by the Analyze modules.
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PUBLIC
SAVE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
INTEGER           :: NAnalyze                    ! number of analyzation points is NAnalyze+1
REAL,ALLOCATABLE  :: wAnalyze(:)                 ! GL integration weights used for the analyze
REAL,ALLOCATABLE  :: Vdm_GaussN_NAnalyze(:,:)    ! for interpolation to Analyze points
REAL              :: Analyze_dt
LOGICAL           :: CalcPoyntingInt             ! calulate pointing vector integral | only perp to z axis
REAL              :: PoyntingIntCoordErr         ! tolerance in plane searching
INTEGER           :: nPoyntingIntPlanes          ! number of planes
REAL,ALLOCATABLE  :: PosPoyntingInt(:)           ! z-coordinate of plane
REAL,ALLOCATABLE  :: PoyntingIntPlaneFactor(:)   ! plane factor
REAL,ALLOCATABLE  :: S(:,:,:,:), STEM(:,:,:)     ! vector, abs for TEM waves
REAL,ALLOCATABLE  :: wGPSurf(:,:)                ! wGPSurf(i,j)=wGP(i)*wGP(j)
!===================================================================================================================================
LOGICAL           :: AnalyzeInitIsDone = .FALSE.
END MODULE MOD_Analyze_Vars