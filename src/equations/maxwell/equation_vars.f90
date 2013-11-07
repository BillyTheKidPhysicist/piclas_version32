MODULE MOD_Equation_Vars
!===================================================================================================================================
! Contains the constant Advection Velocity Vector used for the linear scalar advection equation
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PUBLIC
SAVE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
REAL              :: c_corr
REAL              :: c_corr2    !c_corr^2
REAL              :: c_corr_c   !c_corr*c
REAL              :: c_corr_c2  !c_corr*c^2
REAL              :: eta_c      !(c_corr -1 )*c
REAL              :: fDamping
REAL              :: Pi,spi
INTEGER           :: IniExactFunc
INTEGER           :: BCType(6)=-999
INTEGER           :: BoundaryCondition(6,2)
LOGICAL           :: EquationInitIsDone=.FALSE.
REAL              :: c
REAL              :: c_inv
REAL              :: c2      ! c^2
REAL              :: c2_inv
REAL              :: eps0 
REAL              :: mu0 
REAL              :: smu0
INTEGER           :: alpha_shape
REAL              :: shapeFuncPrefix
REAL              :: rCutoff
CHARACTER(LEN=255),DIMENSION(8),PARAMETER :: StrVarNames(8)=(/ CHARACTER(LEN=255) :: 'ElectricFieldX', &
                                                                                     'ElectricFieldY', &
                                                                                     'ElectricFieldZ', &
                                                                                     'MagneticFieldX', &
                                                                                     'MagneticFieldY', &
                                                                                     'MagneticFieldZ', &
                                                                                     'Phi'           , &
                                                                                     'Psi           ' /)
!===================================================================================================================================
END MODULE MOD_Equation_Vars