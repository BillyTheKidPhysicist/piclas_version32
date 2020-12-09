!==================================================================================================================================
! Copyright (c) 2015 - 2019 Wladimir Reschke
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
MODULE MOD_SurfaceModel_Analyze_Vars
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
LOGICAL                       :: SurfModelAnalyzeInitIsDone = .FALSE.
INTEGER                       :: SurfaceAnalyzeStep                  ! Analyze of surface is performed each Nth time step
LOGICAL                       :: CalcCollCounter                     ! Calculate the number of surface collision and number of
                                                                     ! adsorbed particles per species
LOGICAL                       :: CalcDesCounter                      ! Calculate the number of desorption particle per species
LOGICAL                       :: CalcPorousBCInfo                    !< Calculate output for porous BCs (averaged over whole BC)

REAL,ALLOCATABLE              :: PorousBCOutput(:,:)  ! 1: Counter of impinged particles on the BC
                                                      ! 2: Measured pumping speed [m3/s] through # of deleted particles
                                                      ! 3: Pumping speed [m3/s] used to calculate the removal prob.
                                                      ! 4: Removal probability [0-1]
                                                      ! 5: Pressure at the BC normalized with the user-given pressure
!===================================================================================================================================
END MODULE MOD_SurfaceModel_Analyze_Vars
