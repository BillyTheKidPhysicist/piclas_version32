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
MODULE MOD_DSMC_Vars
!===================================================================================================================================
! Contains the DSMC variables
!===================================================================================================================================
! MODULES
#if USE_MPI
USE MOD_Particle_MPI_Vars, ONLY: tPartMPIConnect
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PUBLIC
SAVE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
TYPE tTLU_Data
  DOUBLE PRECISION                        :: Emin
  DOUBLE PRECISION                        :: Emax
  DOUBLE PRECISION                        :: deltaE
  DOUBLE PRECISION , ALLOCATABLE          :: deltabj(:)
  DOUBLE PRECISION , ALLOCATABLE          :: ChiTable(:,:)
END TYPE

TYPE(tTLU_Data)                           :: TLU_Data


REAL                          :: Debug_Energy(2)=0.0        ! debug variable energy conservation
INTEGER                       :: DSMCSumOfFormedParticles   !number of formed particles per iteration in chemical reactions
                                                            ! for counting the nextfreeparticleposition
REAL  , ALLOCATABLE           :: DSMC_RHS(:,:)              ! RHS of the DSMC Method/ deltaV (npartmax, direction)
INTEGER                       :: CollisMode                 ! Mode of Collision:, ini_1
                                                            !    0: No Collisions (=free molecular flow with DSMC-Sampling-Routines)
                                                            !    1: Elastic Collision
                                                            !    2: Relaxation + Elastic Collision
                                                            !    3: Chemical Reactions
INTEGER                       :: SelectionProc              ! Mode of Selection Procedure:
                                                            !    1: Laux Default
                                                            !    2: Gimmelsheim

INTEGER                       :: PairE_vMPF(2)              ! 1: Pair chosen for energy redistribution
                                                            ! 2: partical with minimal MPF of this Pair
LOGICAL                       :: useDSMC
REAL    , ALLOCATABLE         :: PartStateIntEn(:,:)        ! 1st index: 1:npartmax 
!                                                           ! 2nd index: Evib, Erot, Eel

LOGICAL                       :: useRelaxProbCorrFactor     ! Use the relaxation probability correction factor of Lumpkin

TYPE tVarVibRelaxProb
  REAL, ALLOCATABLE           :: ProbVibAvNew(:)            ! New Average of vibrational relaxation probability (1:nSPecies)
                                                            ! , VibRelaxProb = 2
  REAL, ALLOCATABLE           :: ProbVibAv(:,:)             ! Average of vibrational relaxation probability of the Element
                                                            ! (1:nElems,nSpecies), VibRelaxProb = 2
  INTEGER, ALLOCATABLE        :: nCollis(:)                 ! Number of Collisions (1:nSPecies), VibRelaxProb = 2
  REAL                        :: alpha                      ! Relaxation factor of ProbVib, VibRelaxProb = 2
END TYPE tVarVibRelaxProb

TYPE(tVarVibRelaxProb) VarVibRelaxProb

TYPE tRadialWeighting
  REAL                        :: PartScaleFactor
  INTEGER                     :: NextClone
  INTEGER                     :: CloneDelayDiff
  LOGICAL                     :: DoRadialWeighting          ! Enables radial weighting in the axisymmetric simulations
  LOGICAL                     :: PerformCloning             ! Flag whether the cloning/deletion routine should be performed,
                                                            ! when using radial weighting (e.g. no cloning for the BGK/FP methods)
  INTEGER                     :: CloneMode                  ! 1 = Clone Delay
                                                            ! 2 = Clone Random Delay
  INTEGER, ALLOCATABLE        :: ClonePartNum(:)
  INTEGER                     :: CloneInputDelay
  LOGICAL                     :: CellLocalWeighting
  INTEGER                     :: nSubSides
END TYPE tRadialWeighting

TYPE(tRadialWeighting)        :: RadialWeighting

TYPE tClonedParticles
  ! Clone Delay: Clones are inserted at the next time step
  INTEGER                     :: Species
  REAL                        :: PartState(1:6)
  REAL                        :: PartStateIntEn(1:3)
  INTEGER                     :: Element
  REAL                        :: LastPartPos(1:3)
  REAL                        :: WeightingFactor
  INTEGER, ALLOCATABLE        :: VibQuants(:)
END TYPE

TYPE(tClonedParticles),ALLOCATABLE :: ClonedParticles(:,:)

TYPE tSpecInit
  REAL                        :: TVib                      ! vibrational temperature, ini_1
  REAL                        :: TRot                      ! rotational temperature, ini_1
  REAL                        :: TElec                     ! electronic temperature, ini_1
END TYPE tSpecInit

TYPE tSpeciesDSMC                                          ! DSMC Species Parameter
  TYPE(tSpecInit),ALLOCATABLE :: Init(:) !   =>NULL()
  TYPE(tSpecInit),ALLOCATABLE :: Surfaceflux(:)
  LOGICAL                     :: PolyatomicMol             ! Species is a polyatomic molecule
  INTEGER                     :: SpecToPolyArray           !
  CHARACTER(LEN=64)           :: Name                      ! Species Name, required for DSMCSpeciesElectronicDatabase
  INTEGER                     :: InterID                   ! Identification number (e.g. for DSMC_prob_calc), ini_2
                                                           !     1   : Atom
                                                           !     2   : Molecule
                                                           !     4   : Electron
                                                           !     10  : Atomic ion
                                                           !     15  : Atomic CEX/MEX ion
                                                           !     20  : Molecular ion
                                                           !     40  : Excited atom
                                                           !     100 : Excited atomic ion
                                                           !     200 : Excited molecule
                                                           !     400 : Excited molecular ion
  REAL                        :: Tref                      ! collision model: reference temperature     , ini_2
  REAL                        :: dref                      ! collision model: reference diameter        , ini_2
  REAL                        :: omega                     ! collision model: temperature exponent      , ini_2
  REAL                        :: alphaVSS                  ! collision model: scattering exponent(VSS)  , ini_2
  INTEGER                     :: NumOfPro                  ! Number of Protons, ini_2
  REAL                        :: Eion_eV                   ! Energy of Ionisation in eV, ini_2
  REAL                        :: RelPolarizability         ! relative polarizability, ini_2
  INTEGER                     :: NumEquivElecOutShell      ! number of equivalent electrons in outer shell, ini2
  INTEGER                     :: Xi_Rot                    ! Rotational DOF
  REAL                        :: GammaVib                  ! GammaVib = Xi_Vib(T_t)² * exp(CharaTVib/T_t) / 2 -> correction fact
                                                           ! for vib relaxation -> see 'Vibrational relaxation rates
                                                           ! in the DSMC method', Gimelshein et al., 2002
  REAL                        :: CharaTVib                 ! Characteristic vibrational Temp, ini_2
  REAL                        :: Ediss_eV                  ! Energy of dissociation in eV, ini_2
  INTEGER                     :: MaxVibQuant               ! Max vib quantum number + 1
  INTEGER                     :: MaxElecQuant              ! Max elec quantum number + 1
  INTEGER                     :: DissQuant                 ! Vibrational quantum number corresponding to the dissociation energy
                                                           ! (used for QK chemistry, not using MaxVibQuant to avoid confusion with
                                                           !   the truncated simple harmonic oscillator(TSHO) model)
  REAL                        :: RotRelaxProb              ! rotational relaxation probability
  REAL                        :: VibRelaxProb              ! vibrational relaxation probability
  REAL                        :: ElecRelaxProb             ! electronic relaxation probability
                                                           !this should be a value for every transition, and not fix!
  REAL                        :: VFD_Phi3_Factor           ! Factor of Phi3 in VFD Method: Phi3 = 0 => VFD -> TCE, ini_2
  REAL                        :: CollNumRotInf             ! Collision number for rotational relaxation according to Parker or
                                                           ! Zhang, ini_2 -> model dependent!
  REAL                        :: TempRefRot                ! Reference temperature for rotational relaxation according to Parker or
                                                           ! Zhang, ini_2 -> model dependent!
  REAL, ALLOCATABLE           :: MW_ConstA(:)              ! Model Constant 'A' of Milikan-White Model for vibrational relax, ini_2
  REAL, ALLOCATABLE           :: MW_ConstB(:)              ! Model Constant 'B' of Milikan-White Model for vibrational relax, ini_2
  REAL, ALLOCATABLE           :: CollNumVib(:)             ! vibrational collision number
  REAL                        :: VibCrossSec               ! vibrational cross section, ini_2
  REAL, ALLOCATABLE           :: CharaVelo(:)              ! characteristic velocity according to Boyd & Abe, nec for vib
                                                           ! relaxation
  REAL,ALLOCATABLE,DIMENSION(:,:)   :: ElectronicState      ! Array with electronic State for each species
                                                            ! first  index: 1 - degeneracy & 2 - char. Temp,el
                                                            ! second index: energy level
  INTEGER                           :: SymmetryFactor
  REAL                              :: CharaTRot
  REAL, ALLOCATABLE                 :: PartitionFunction(:) ! Partition function for each species in given temperature range
  REAL                              :: EZeroPoint           ! Zero point energy for molecules
  REAL                              :: HeatOfFormation      ! Heat of formation of the respective species [Kelvin]
  INTEGER                           :: PreviousState        ! Species number of the previous state (e.g. N for NIon)
  LOGICAL                           :: FullyIonized         ! Flag if the species is fully ionized (e.g. C^6+)
  INTEGER                           :: NextIonizationSpecies! SpeciesID of the next higher ionization level (required for field
                                                            ! ionization)
  ! Collision cross-sections for MCC
  LOGICAL                           :: UseCollXSec          ! Flag if the collisions of the species with a background gas should be
                                                            ! treated with read-in collision cross-section (currently only with BGG)
  LOGICAL                           :: UseVibXSec           ! Flag if the vibrational relaxation probability should be treated,
                                                            ! using read-in cross-sectional data (currently only with BGG)
END TYPE tSpeciesDSMC

TYPE(tSpeciesDSMC), ALLOCATABLE     :: SpecDSMC(:)          ! Species DSMC params (nSpec)

TYPE tXSecData
  REAL,ALLOCATABLE                  :: XSecData(:,:)        ! Cross-section as read-in from the database
                                                            ! 1: Energy (at read-in in [eV], during simulation in [J])
                                                            ! 2: Cross-section at the respective energy level [m^2]
  REAL                              :: Prob                 ! Event probability
END TYPE tXSecData

TYPE tSpeciesXSec
  LOGICAL                           :: UseCollXSec          ! Flag if the collisions of the species pair should be treated with
                                                            ! read-in collision cross-section (currently only with BGG)
  LOGICAL                           :: CollXSec_Effective   ! Flag whether the given cross-section data is "effective" (complete set
                                                            ! including other processes such as e.g.excitation and ionization) or
                                                            ! "elastic", including only the elastic collision cross-section.
  REAL                              :: CrossSection         ! Current collision cross-section
  REAL,ALLOCATABLE                  :: CollXSecData(:,:)    ! Collision cross-section as read-in from the database
                                                            ! 1: Energy (at read-in in [eV], during simulation in [J])
                                                            ! 2: Cross-section at the respective energy level [m^2]
  REAL,ALLOCATABLE                  :: VibXSecData(:,:)     ! Vibrational cross-section as read-in from the database
                                                            ! 1: Energy (at read-in in [eV], during simulation in [J])
                                                            ! 2: Cross-section at the respective energy level [m^2]
  REAL                              :: ProbNull             ! Collision probability at the maximal collision frequency for the
                                                            ! null collision method of MCC
  LOGICAL                           :: UseVibXSec           ! Flag if cross-section data will be used for the relaxation probability
  TYPE(tXSecData),ALLOCATABLE       :: VibMode(:)           ! Vibrational cross-sections (nVib: Number of levels found in database)
  REAL                              :: VibProb              ! Relaxation probability
  REAL                              :: VibCount             ! Event counter
  INTEGER                           :: SpeciesToRelax       ! Save which species shall use the vibrational cross-sections
  TYPE(tXSecData),ALLOCATABLE       :: ReactionPath(:)      ! Reaction cross-sections (nPaths: Number of reactions for that case)
END TYPE tSpeciesXSec

TYPE(tSpeciesXSec), ALLOCATABLE     :: SpecXSec(:)          ! Species cross-section related data (CollCase)

TYPE tDSMC
  INTEGER                       :: ElectronSpecies          ! Species of the electron
  REAL                          :: EpsElecBin               ! percentage parameter of electronic energy level merging
  REAL                          :: GammaQuant               ! GammaQuant for zero point energy in Evib (perhaps also Erot),
                                                            ! should be 0.5 or 0
  REAL, ALLOCATABLE             :: NumColl(:)               ! Number of Collision for each case + entire Collision number
  REAL                          :: TimeFracSamp=0.          ! %-of simulation time for sampling
  INTEGER                       :: SampNum                  ! number of Samplingsteps
  INTEGER                       :: NumOutput                ! number of Outputs
  REAL                          :: DeltaTimeOutput          ! Time intervall for Output
  LOGICAL                       :: ReservoirSimu            ! Flag for reservoir simulation
  LOGICAL                       :: ReservoirSimuRate        ! Does not performe the collision.
                                                            ! Switch to enable to create reaction rates curves
  LOGICAL                       :: ReservoirSurfaceRate     ! Switch enabling surface rate output without changing surface coverages
  LOGICAL                       :: ReservoirRateStatistic   ! if false, calculate the reaction coefficient rate by the probability
                                                            ! Default Value is false
  INTEGER                       :: VibEnergyModel           ! Model for vibration Energy:
                                                            !       0: SHO (default value!)
                                                            !       1: TSHO
  LOGICAL                       :: DoTEVRRelaxation         ! Flag for T-V-E-R or more simple T-V-R T-E-R relaxation
  INTEGER                       :: PartNumOctreeNode        ! Max Number of Particles per Octree Node
  INTEGER                       :: PartNumOctreeNodeMin     ! Min Number of Particles per Octree Node
  LOGICAL                       :: UseOctree                ! Flag for Octree
  LOGICAL                       :: UseNearestNeighbour      ! Flag for Nearest Neighbour or classic statistical pairing
  LOGICAL                       :: CalcSurfaceVal           ! Flag for calculation of surfacevalues like heatflux or force at walls
  LOGICAL                       :: CalcSurfaceTime          ! Flag for sampling in time-domain or iterations
  REAL                          :: CalcSurfaceSumTime       ! Flag for sampling in time-domain or iterations
  REAL                          :: CollProbMean             ! Summation of collision probability
  REAL                          :: CollProbMax              ! Maximal collision probability per cell
  REAL, ALLOCATABLE             :: CalcRotProb(:,:)         ! Summation of rotation relaxation probability (nSpecies + 1,3)
                                                            !     1: Mean Prob
                                                            !     2: Max Prob
                                                            !     3: Sample size
  REAL, ALLOCATABLE             :: CalcVibProb(:,:)         ! Summation of vibration relaxation probability (nSpecies + 1,3)
                                                            !     1: Mean Prob
                                                            !     2: Max Prob
                                                            !     3: Sample size
  REAL                          :: MeanFreePath
  REAL                          :: MCSoverMFP               ! Subcell local mean collision distance over mean free path
  INTEGER                       :: CollProbMeanCount        ! counter of possible collision pairs
  INTEGER                       :: CollSepCount             ! counter of actual collision pairs
  REAL                          :: CollSepDist              ! Summation of mean collision separation distance
  LOGICAL                       :: CalcQualityFactors       ! Enables/disables the calculation and output of flow-field variables
  REAL, ALLOCATABLE             :: QualityFacSamp(:,:)      ! Sampling of quality factors
                                                            !     1: Maximal collision prob
                                                            !     2: Time-averaged mean collision prob
                                                            !     3: Mean collision separation distance over mean free path
                                                            !     4: Sample size
  REAL, ALLOCATABLE             :: QualityFacSampRot(:,:,:) ! Sampling of quality rot relax factors (nElem,nSpec+1,2)
                                                            !     1: Time-averaged mean rot relax prob
                                                            !     2: Maximal rot relax prob
  INTEGER, ALLOCATABLE          :: QualityFacSampRotSamp(:,:)!Sample size for QualityFacSampRot
  REAL, ALLOCATABLE             :: QualityFacSampVib(:,:,:) ! Sampling of quality vib relax factors (nElem,nSpec+1,2)
                                                            !     1: Instantanious time-averaged mean vib relax prob
                                                            !     2: Instantanious maximal vib relax prob
  INTEGER, ALLOCATABLE          :: QualityFacSampVibSamp(:,:,:)!Sample size for QualityFacSampVib
  REAL, ALLOCATABLE             :: QualityFacSampRelaxSize(:,:)! Samplie size of quality relax factors (nElem,nSpec+1)
  LOGICAL                       :: ElectronicModel          ! Flag for Electronic State of atoms and molecules
  CHARACTER(LEN=64)             :: ElectronicModelDatabase  ! Name of Electronic State Database | h5 file
  INTEGER                       :: NumPolyatomMolecs        ! Number of polyatomic molecules
  REAL                          :: RotRelaxProb             ! Model for calculation of rotational relaxation probability, ini_1
                                                            !    0-1: constant probability  (0: no relaxation)
                                                            !    2: Boyd's model
                                                            !    3: Nonequilibrium Direction Dependent model (Zhang,Schwarzentruber)
  REAL                          :: VibRelaxProb             ! Model for calculation of vibrational relaxation probability, ini_1
                                                            !    0-1: constant probability (0: no relaxation)
                                                            !    2: Boyd's model, with correction from Abe
  REAL                          :: ElecRelaxProb            ! electronic relaxation probability
  LOGICAL                       :: PolySingleMode           ! Separate relaxation of each vibrational mode of a polyatomic in a
                                                            ! loop over all vibrational modes (every mode has its own corrected
                                                            ! relaxation probability, comparison with the same random number
                                                            ! while the previous probability is added to the next)
  REAL, ALLOCATABLE             :: InstantTransTemp(:)      ! Instantaneous translational temprerature for each cell (nSpieces+1)
  LOGICAL                       :: BackwardReacRate         ! Enables the automatic calculation of the backward reaction rate
                                                            ! coefficient with the equilibrium constant by partition functions
  REAL                          :: PartitionMaxTemp         ! Temperature limit for pre-stored partition function (DEF: 20 000K)
  REAL                          :: PartitionInterval        ! Temperature interval for pre-stored partition function (DEF: 10K)
#if (PP_TimeDiscMethod==42)
  LOGICAL                       :: CompareLandauTeller      ! Keeps the translational temperature at the fixed value of the init
#endif
  LOGICAL                       :: MergeSubcells            ! Merge subcells after quadtree division if number of particles within
                                                            ! subcell is less than 7
END TYPE tDSMC

TYPE(tDSMC)                     :: DSMC

TYPE tBGGas
  INTEGER                       :: NumberOfSpecies          ! Number of background gas species
  LOGICAL, ALLOCATABLE          :: BackgroundSpecies(:)     ! Flag, if a species is a background gas species, [1:nSpecies]
  INTEGER, ALLOCATABLE          :: MapSpecToBGSpec(:)       ! Input: [1:nSpecies], output is the corresponding background species
  REAL, ALLOCATABLE             :: SpeciesFraction(:)       ! Fraction of background species (sum is 1), [1:BGGas%NumberOfSpecies]
  REAL, ALLOCATABLE             :: NumberDensity(:)         ! Number densities of the background gas, [1:BGGas%NumberOfSpecies]
  INTEGER, ALLOCATABLE          :: PairingPartner(:)        ! Index of the background particle generated for the pairing with a
                                                            ! regular particle
END TYPE tBGGas

TYPE(tBGGas)                    :: BGGas

LOGICAL                             :: UseMCC               ! Flag (set automatically) to differentiate between MCC/XSec and regular DSMC
CHARACTER(LEN=256)                  :: XSec_Database        ! Name of the cross-section database
LOGICAL                             :: XSec_NullCollision   ! Flag (read-in) whether null collision method (determining number of pairs based on maximum relaxation frequency)
LOGICAL                             :: XSec_Relaxation      ! Flag (set automatically): usage of XSec data for the total relaxation probability
INTEGER                             :: MCC_TotalPairNum     ! Total number of collision pairs for the MCC method

TYPE tPairData
  REAL                          :: CRela2                       ! squared relative velo of the particles in a pair
  REAL                          :: Prob                         ! collision probability
  INTEGER                       :: iPart_p1                     ! first particle of the pair
  INTEGER                       :: iPart_p2                     ! second particle of the pair
  INTEGER                       :: PairType                     ! type of pair (=iCase, CollInf%Coll_Case)
  REAL, ALLOCATABLE             :: Sigma(:)                     ! cross sections sigma of the pair
                                                                  !       0: sigma total
                                                                  !       1: sigma elast
                                                                  !       2: sigma ionization
                                                                  !       3: sigma excitation
  REAL                          :: Ec                           ! Collision Energy
  LOGICAL                       :: NeedForRec                   ! Flag if pair is needed for Recombination
END TYPE tPairData

TYPE(tPairData), ALLOCATABLE    :: Coll_pData(:)                ! Data of collision pairs into a cell (nPair)

TYPE tCollInf     ! Collision information
  INTEGER                       :: crossSectionConstantMode     ! Flags how cross section constant Cab(Laux1996) is calculated.
                                                                ! sigma=Cab * cr^(-2 omega).
                                                                !   0: single omega for the computational domain + A_j calculation
                                                                !   1: Cab will be calculated via species-specific factor A_j
                                                                !   2: Cab will be calculated directly see Bird1981 eq (9)
  LOGICAL                       :: averagedCollisionParameters  ! Flags if coll-specific(F) or -averaged(T) collision parameters:
                                                                ! Tref, dref, omega, alphaVSS
  INTEGER       , ALLOCATABLE   :: collidingSpecies(:,:)        ! Contains colliding species ini file IDs. e.g. collision #iColl
                                                                ! are Species1 and Species2: collidingSpecies(iColl,:)=(/1,2/)
  INTEGER       , ALLOCATABLE   :: Coll_Case(:,:)               ! Case of species combination (Spec1, Spec2)
  INTEGER                       :: NumCase                      ! number of possible collision combinations
  INTEGER       , ALLOCATABLE   :: Coll_CaseNum(:)              ! number of simulated species combinations per cell Sab (#of cases)
  REAL          , ALLOCATABLE   :: Coll_SpecPartNum(:)          ! number of simulated particles of species n per cell (nSpec)
  REAL          , ALLOCATABLE   :: Cab(:)                       ! species factor for cross section (#of case)
  INTEGER       , ALLOCATABLE   :: KronDelta(:)                 ! (number of case)
  REAL          , ALLOCATABLE   :: FracMassCent(:,:)            ! mx/(my+mx) (nSpec, number of cases)
  REAL          , ALLOCATABLE   :: MeanMPF(:)
  REAL          , ALLOCATABLE   :: MassRed(:)                   ! reduced mass (number of cases)
  REAL          , ALLOCATABLE   :: Tref(:,:)                    ! collision model: reference temperature     , ini_2
  REAL          , ALLOCATABLE   :: dref(:,:)                    ! collision model: reference diameter        , ini_2
  REAL          , ALLOCATABLE   :: omega(:,:)               ! collision model: temperature exponent      , ini_2
  REAL          , ALLOCATABLE   :: alphaVSS(:,:)                ! collision model: scattering exponent (VSS) , ini_2
  LOGICAL                       :: ProhibitDoubleColl = .FALSE.
  INTEGER       , ALLOCATABLE   :: OldCollPartner(:)            ! index of old coll partner to prohibit double collisions(maxPartNum)
END TYPE

TYPE(tCollInf)                  :: CollInf

TYPE tSampDSMC             ! DSMC sample
  REAL                          :: PartV(3), PartV2(3)     ! Velocity, Velocity^2 (vx,vy,vz)
  REAL                          :: PartNum                 ! Particle Number
  INTEGER                       :: SimPartNum
  REAL                          :: ERot                    ! Rotational  energy
  REAL                          :: EVib                    ! Vibrational energy
  REAL                          :: EElec                   ! Electronic  energy
END TYPE

TYPE(tSampDSMC), ALLOCATABLE    :: SampDSMC(:,:)           ! DSMC sample array (number of Elements, nSpec)

TYPE tMacroDSMC           ! DSMC output
  REAL                           :: PartV(4), PartV2(3)    ! Velocity, Velocity^2 (vx,vy,vz,|v|)
  REAL                           :: PartNum                ! Particle Number
  REAL                           :: Temp(4)                ! Temperature (Tx, Ty, Tz, Tt)
  REAL                           :: NumDens                ! Particle density
  REAL                           :: TVib                   ! Vibrational Temp
  REAL                           :: TRot                   ! Rotational Temp
  REAL                           :: TElec                  ! Electronic Temp
END TYPE

TYPE(tMacroDSMC), ALLOCATABLE     :: MacroDSMC(:,:)         ! DSMC sample array (number of Elements, nSpec)

TYPE tCollCaseInfo
  INTEGER                         :: NumOfReactionPaths     ! Number of possible reaction paths for the collision pair
  INTEGER, ALLOCATABLE            :: ReactionIndex(:)       ! Reaction index as in ChemReac%NumOfReact (1:NumOfReactionPaths)
  REAL, ALLOCATABLE               :: ReactionProb(:)        ! Reaction probability (1:NumOfReactionPaths)
  LOGICAL, ALLOCATABLE            :: QK_PerformReaction(:)  ! Flag whether a QK reaction is to be performed (1:NumOfReactionPaths)
  LOGICAL                         :: HasXSecReaction
END TYPE

TYPE tReactInfo
  REAL,  ALLOCATABLE              :: Beta_Arrhenius(:,:)    ! Beta for calculation of the reaction probability by TCE
                                                            ! (quant number species 1, quant number species 2)
  REAL,  ALLOCATABLE              :: Beta_Rec_Arrhenius(:,:)! Beta_d for calculation of the Recombination reaction probability
                                                            ! (nSpecies, quant num part3)
  INTEGER, ALLOCATABLE            :: StoichCoeff(:,:)       ! Stoichiometric coefficient (nSpecies,1:2) (1: reactants, 2: products)
END TYPE

TYPE tArbDiss
  INTEGER                         :: NumOfNonReactives      ! Number of non-reactive collisions partners
  INTEGER, ALLOCATABLE            :: NonReactiveSpecies(:)  ! Array with the non-reactive collision partners for dissociation
END TYPE

TYPE tChemReactions
  INTEGER                         :: NumOfReact             ! Number of possible reactions
  TYPE(tArbDiss), ALLOCATABLE     :: ArbDiss(:)             ! Construct to allow the definition of a list of non-reactive educts
  LOGICAL, ALLOCATABLE            :: QKProcedure(:)         ! Defines if QK Procedure is selected
  REAL, ALLOCATABLE               :: QKRColl(:)             ! Collision factor in QK model
  REAL, ALLOCATABLE               :: QKTCollCorrFac(:)      ! Correction factor for collision temperature due to averaging over T^b
  REAL, ALLOCATABLE               :: NumReac(:)             ! Number of occurred reactions for each reaction number
  INTEGER, ALLOCATABLE            :: ReacCount(:)           ! Counter of chemical reactions for the determination of rate
                                                            ! coefficient based on the reaction probabilities
  REAL, ALLOCATABLE               :: ReacCollMean(:)        ! Mean collision probability for each collision pair
  CHARACTER(LEN=5),ALLOCATABLE    :: ReactType(:)           ! Type of Reaction (reaction num)
                                                            !    i (electron impact ionization)
                                                            !    R (molecular recombination
                                                            !    D (molecular dissociation)
                                                            !    E (molecular exchange reaction)
                                                            !    x (simple charge exchange reaction)
  INTEGER, ALLOCATABLE            :: Reactants(:,:)         ! Reactants: indices of the species starting the reaction [NumOfReact,3]
  INTEGER, ALLOCATABLE            :: Products(:,:)          ! Products: indices of the species resulting from the reaction [NumOfReact,4]
  INTEGER, ALLOCATABLE            :: ReactCase(:)           ! Case/pair of the reaction (1:NumOfReact)
  INTEGER, ALLOCATABLE            :: ReactNum(:,:,:)            ! Number of Reaction of (spec1, spec2,
                                                                ! Case 16: simple CEX, only 1
  INTEGER, ALLOCATABLE            :: ReactNumRecomb(:,:,:)      ! Number of Reaction of (spec1, spec2, spec3)
  REAL,  ALLOCATABLE              :: Arrhenius_Prefactor(:)     ! pre-exponential factor af of Arrhenius ansatz (nReactions)
  REAL,  ALLOCATABLE              :: Arrhenius_Powerfactor(:)   ! powerfactor bf of temperature in Arrhenius ansatz (nReactions)
  REAL,  ALLOCATABLE              :: EActiv(:)              ! activation energy (relative to k) (nReactions)
  REAL,  ALLOCATABLE              :: EForm(:)               ! heat of formation  (relative to k) (nReactions)
  REAL,  ALLOCATABLE              :: MeanEVib_PerIter(:)    ! MeanEVib per iteration for calculation of
  INTEGER,  ALLOCATABLE           :: MeanEVibQua_PerIter(:) ! MeanEVib per iteration for calculation of
                                                            ! xi_vib per cell (nSpecies)
  REAL, ALLOCATABLE               :: MeanXiVib_PerIter(:)   ! Mean vibrational degree of freedom user for chemical reactions of
                                                            ! diatomic species
  REAL,  ALLOCATABLE              :: CEXa(:)                ! CEX log-factor (g-dep. cross section in Angstrom (nReactions)
  REAL,  ALLOCATABLE              :: CEXb(:)                ! CEX const. factor (g-dep. cross section in Angstrom (nReactions)
  REAL,  ALLOCATABLE              :: MEXa(:)                ! MEX log-factor (g-dep. cross section in Angstrom (nReactions)
  REAL,  ALLOCATABLE              :: MEXb(:)                ! MEX const. factor (g-dep. cross section in Angstrom (nReactions)
  REAL,  ALLOCATABLE              :: ELa(:)                 ! EL log-factor (g&cut-off-angle-dep. cs in Angstrom (nReactions)
  REAL,  ALLOCATABLE              :: ELb(:)                 ! EL const. factor (g&cut-off-angle-dep. cs in Angstrom (nReactions)
  LOGICAL, ALLOCATABLE            :: DoScat(:)              ! Do Scattering Calculation by Lookup table
  CHARACTER(LEN=200),ALLOCATABLE  :: TLU_FileName(:)        ! Name of file containing table lookup data for Scattering
  INTEGER                         :: RecombParticle = 0     ! P. Index for Recombination, if zero -> no recomb particle avaible
  INTEGER                         :: nPairForRec            !
  INTEGER                         :: LastPairForRec         !
  REAL, ALLOCATABLE               :: Hab(:)                 ! Factor Hab of Arrhenius Ansatz for diatomic/polyatomic molecs
  TYPE(tReactInfo), ALLOCATABLE   :: ReactInfo(:)           ! Information of Reactions (nReactions)
  INTEGER                         :: NumDeleteProducts      ! Number of species to be considered to deletion after the reaction
  INTEGER, ALLOCATABLE            :: DeleteProductsList(:)  ! Indices of the species to be deleted [1:NumDeleteProducts]
  REAL, ALLOCATABLE               :: CrossSection(:)        ! Cross-section of the given photo-ionization reaction
  TYPE(tCollCaseInfo), ALLOCATABLE:: CollCaseInfo(:)        ! Information of collision cases (nCase)
  ! XSec Chemistry
  LOGICAL, ALLOCATABLE            :: XSec_Procedure(:)      ! Defines if reaction is based on cross-section data
END TYPE

TYPE(tChemReactions)              :: ChemReac


TYPE tQKChemistry
  REAL, ALLOCATABLE               :: ForwardRate(:)
END TYPE

TYPE(tQKChemistry), ALLOCATABLE   :: QKChemistry(:)

TYPE tPolyatomMolDSMC !DSMC Species Param
  LOGICAL                         :: LinearMolec            ! Is a linear Molec?
  INTEGER                         :: NumOfAtoms             ! Number of Atoms in Molec
  INTEGER                         :: VibDOF                 ! DOF in Vibration, equals number of independent SHO's
  REAL, ALLOCATABLE               :: CharaTVibDOF(:)        ! Chara TVib for each DOF
  INTEGER,ALLOCATABLE             :: LastVibQuantNums(:,:)  ! Last quantum numbers for vibrational inserting (VibDOF,nInits)
  INTEGER, ALLOCATABLE            :: MaxVibQuantDOF(:)      ! Max Vib Quant for each DOF
  REAL, ALLOCATABLE               :: GammaVib(:)            ! GammaVib: correction factor for Gimelshein Relaxation Procedure
  REAL, ALLOCATABLE               :: VibRelaxProb(:)
  REAL, ALLOCATABLE               :: CharaTRotDOF(:)        ! Chara TRot for each DOF
END TYPE

TYPE (tPolyatomMolDSMC), ALLOCATABLE    :: PolyatomMolDSMC(:)        ! Infos for Polyatomic Molecule

TYPE tPolyatomMolVibQuant !DSMC Species Param
  INTEGER, ALLOCATABLE            :: Quants(:)            ! Vib quants of each DOF for each particle
END TYPE

TYPE (tPolyatomMolVibQuant), ALLOCATABLE    :: VibQuantsPar(:)

REAL,ALLOCATABLE                  :: MacroSurfaceVal(:,:,:,:)      ! variables,p,q,sides
REAL,ALLOCATABLE                  :: MacroSurfaceSpecVal(:,:,:,:,:)! Macrovalues for Species specific surface output
                                                                   ! (4,p,q,nSurfSides,nSpecies)
                                                                   ! 1: Surface Collision Counter
                                                                   ! 2: Accomodation
                                                                   ! 3: Coverage
                                                                   ! 4 (or 2): Impact energy trans
                                                                   ! 5 (or 3): Impact energy rot
                                                                   ! 6 (or 4): Impact energy vib

! some variables redefined
!TYPE tMacroSurfaceVal                                       ! DSMC sample for Wall
!  REAL                           :: Heatflux                !
!  REAL                           :: Force(3)                ! x, y, z direction
!  REAL, ALLOCATABLE              :: Counter(:)              ! Wall-Collision counter of all Species
!  REAL                           :: CounterOut              ! Wall-Collision counter for Output
!END TYPE
!
!TYPE(tMacroSurfaceVal), ALLOCATABLE     :: MacroSurfaceVal(:) ! Wall sample array (number of BC-Sides)

! MacValout and MacroVolSample have to be separated due to autoinitialrestart
INTEGER(KIND=8)                  :: iter_macvalout             ! iterations since last macro volume output
INTEGER(KIND=8)                  :: iter_macsurfvalout         ! iterations since last macro surface output
!----------------------------------------------convergence criteria-------------------------------------------------
LOGICAL                          :: SamplingActive             ! Identifier if DSMC Sampling is activated
LOGICAL                          :: UseQCrit                   ! Identifier if Q-Criterion (Burt,Boyd) for
                                                               ! Sampling Start is used
INTEGER                          :: QCritTestStep              ! Time Steps between Q criterion evaluations
                                                               ! (=Length of Analyze Interval)
INTEGER(KIND=8)                  :: QCritLastTest              ! Time Step of last Q criterion evaluation
REAL                             :: QCritEpsilon               ! Steady State if Q < 1 + Qepsilon
INTEGER, ALLOCATABLE             :: QCritCounter(:,:)          ! Exit / Wall Collision Counter for
                                                               ! each boundary side (Side, Interval)
REAL, ALLOCATABLE                :: QLocal(:)                  ! Intermediate Criterion (per cell)
LOGICAL                          :: UseSSD                     ! Identifier if Steady-State-Detection
                                                               ! for Sampling Start is used (only  if UseQCrit=FALSE)
INTEGER                          :: ReactionProbGTUnityCounter ! Count the number of ReactionProb>1 (turn off the warning after
!                                                              ! reaching 1000 outputs of said warning

TYPE tSampler ! DSMC sampling for Steady-State Detection       ! DSMC sampling for Steady-State Detection
  REAL                           :: Energy(3)                  ! Energy in Cell (Translation)
  REAL                           :: Velocity(3)                ! Velocity in Cell (x,y,z)
  REAL                           :: PartNum                    ! Particle Number in Cell
  REAL                           :: ERot                       ! Energy in Cell (Rotation)
  REAL                           :: EVib                       ! Energy of Cell (Vibration)
  REAL                           :: EElec                      ! Energy of Cell (Electronic State)
END TYPE

TYPE (tSampler), ALLOCATABLE     :: Sampler(:,:)               ! DSMC sample array (number of Elements, number of Species)
TYPE (tSampler), ALLOCATABLE     :: History(:,:,:)             ! History of Averaged Values (number of Elements,
                                                               ! number of Species, number of Samples)
INTEGER                          :: iSamplingIters             ! Counter for Sampling Iteration
INTEGER                          :: nSamplingIters             ! Number of Iterations for one Sampled Value (Sampling Period)
INTEGER                          :: HistTime                   ! Counter for Sampled Values in History
INTEGER                          :: nTime                      ! Length of History of Sampled Values
                                                               ! (Determines Sample Size for Statistical Tests)
REAL, ALLOCATABLE                :: CheckHistory(:,:)          ! History Array for Detection Algorithm
                                                               ! (number of Elements, number of Samples)
INTEGER, ALLOCATABLE             :: SteadyIdentGlobal(:,:)     ! Identifier if Domain ist stationary (number of Species, Value)
INTEGER, ALLOCATABLE             :: SteadyIdent(:,:,:)         ! Identifier if Cell is stationary
                                                               ! (number of Elements, number of Species, Value)
REAL                             :: Critical(2)                ! Critical Values for the Von-Neumann-Ratio
REAL, ALLOCATABLE                :: RValue(:)                  ! Von-Neumann-Ratio (number of Elements)
REAL                             :: Epsilon1, Epsilon2         ! Parameters for the Critical Values of
                                                               ! the Euclidean Distance method
REAL, ALLOCATABLE                :: ED_Delta(:)                ! Offset of Euclidian Distance Statistic to stationary
                                                               ! value (number of Elements)
REAL                             :: StudCrit                   ! Critical Value for the Student-t Test
REAL, ALLOCATABLE                :: Stud_Indicator(:)          ! Stationary Index of the Student-t Test
                                                               ! (0...1, 1 = steady  state) (number of Elements)
REAL                             :: PITCrit                    ! Critical Value for the Polynomial Interpolation Test
REAL, ALLOCATABLE                :: ConvCoeff(:)               ! Convolution Coefficients (Savizky-Golay-Filter)
                                                               ! for the Polynomial Interpolation Test
REAL, ALLOCATABLE                :: PIT_Drift(:)               ! Relative Filtered Trend Index (<1 = steady state) (number of elements)
REAL, ALLOCATABLE                :: MK_Trend(:)                ! Normalized Trend Parameter for the Mann - Kendall - Test
                                                               ! (-1<x<1 = steady state) (number of Elements)
REAL, ALLOCATABLE                :: HValue(:)                  ! Entropy Parameter (Boltzmann's H-Theorem) (number of Elements)
!-----------------------------------------------convergence criteria-------------------------------------------------

INTEGER, ALLOCATABLE      :: SymmetrySide(:,:)
REAL,ALLOCATABLE          :: DSMC_Solution(:,:,:) !1:3 v, 4:6 v^2, 7 dens, 8 Evib, 9 erot, 10 eelec
REAL,ALLOCATABLE          :: DSMC_VolumeSample(:)         !sampnum samples of volume in element

TYPE tTreeNode
!  TYPE (tTreeNode), POINTER       :: One, Two, Three, Four, Five, Six, Seven, Eight !8 Childnodes of Octree Treenode
  TYPE (tTreeNode), POINTER       :: ChildNode       => null()       !8 Childnodes of Octree Treenode
  REAL                            :: MidPoint(1:3)          ! approx Middle Point of Treenode
  INTEGER                         :: PNum_Node              ! Particle Number of Treenode
  INTEGER, ALLOCATABLE            :: iPartIndx_Node(:)      ! Particle Index List of Treenode
  REAL, ALLOCATABLE               :: MappedPartStates(:,:)  ! PartPos in [-1,1] Space
  LOGICAL, ALLOCATABLE            :: MatchedPart(:)         ! Flag signaling that mapped particle is inside of macroparticle
  REAL                            :: NodeVolume(8)
  INTEGER                         :: NodeDepth
END TYPE

TYPE tNodeVolume
    TYPE (tNodeVolume), POINTER             :: SubNode1 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode2 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode3 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode4 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode5 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode6 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode7 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode8 => null()
    REAL                                    :: Volume
    REAL                                    :: Area
    REAL                                    :: Length
    REAL,ALLOCATABLE                        :: PartNum(:,:)
END TYPE

TYPE tElemNodeVolumes
    TYPE (tNodeVolume), POINTER             :: Root => null()
END TYPE

TYPE (tElemNodeVolumes), ALLOCATABLE        :: ElemNodeVol(:)

TYPE tOctreeVdm
  TYPE (tOctreeVdm), POINTER                :: SubVdm => null()
  REAL,ALLOCATABLE                          :: Vdm(:,:)
  REAL                                      :: wGP
  REAL,ALLOCATABLE                          :: xGP(:)
END TYPE

TYPE (tOctreeVdm), POINTER                  :: OctreeVdm => null()
!===================================================================================================================================
END MODULE MOD_DSMC_Vars
