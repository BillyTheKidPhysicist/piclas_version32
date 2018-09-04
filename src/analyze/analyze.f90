#include "boltzplatz.h"

MODULE MOD_Analyze
!===================================================================================================================================
! Contains DG analyze 
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!===================================================================================================================================
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
!===================================================================================================================================

! GLOBAL VARIABLES 
INTERFACE InitAnalyze
  MODULE PROCEDURE InitAnalyze
END INTERFACE

INTERFACE FinalizeAnalyze
  MODULE PROCEDURE FinalizeAnalyze
END INTERFACE

INTERFACE CalcError
  MODULE PROCEDURE CalcError
END INTERFACE

INTERFACE AnalyzeToFile
  MODULE PROCEDURE AnalyzeToFile
END INTERFACE

INTERFACE PerformAnalyze
  MODULE PROCEDURE PerformAnalyze
END INTERFACE

!===================================================================================================================================
PUBLIC:: InitAnalyze, FinalizeAnalyze, PerformAnalyze 
!===================================================================================================================================
PUBLIC::DefineParametersAnalyze

CONTAINS

!==================================================================================================================================
!> Define parameters 
!==================================================================================================================================
SUBROUTINE DefineParametersAnalyze()
! MODULES
USE MOD_ReadInTools ,ONLY: prms
!USE MOD_AnalyzeEquation ,ONLY: DefineParametersAnalyzeEquation
IMPLICIT NONE
!==================================================================================================================================
CALL prms%SetSection("Analyze")
CALL prms%CreateLogicalOption('DoCalcErrorNorms' , 'Set true to compute L2 and LInf error norms at analyze step.','.FALSE.')
CALL prms%CreateRealOption(   'Analyze_dt'       , 'Specifies time intervall at which analysis routines are called.','0.')
CALL prms%CreateIntOption(    'NAnalyze'         , 'Polynomial degree at which analysis is performed (e.g. for L2 errors).\n'//&
                                                   'Default: 2*N.')
CALL prms%CreateIntOption(    'nSkipAnalyze'     , '(Skip Analyze-Dt)')
CALL prms%CreateLogicalOption('CalcTimeAverage'  , 'Flag if time averaging should be performed')
CALL prms%CreateStringOption( 'VarNameAvg'       , 'Count of time average variables',multiple=.TRUE.)
CALL prms%CreateStringOption( 'VarNameFluc'      , 'Count of fluctuation variables',multiple=.TRUE.)
CALL prms%CreateIntOption(    'nSkipAvg'         , 'Iter every which CalcTimeAverage is performed')
!CALL prms%CreateLogicalOption('AnalyzeToFile',   "Set true to output result of error norms to a file (DoCalcErrorNorms=T)",&
                                                 !'.FALSE.')
!CALL prms%CreateIntOption(    'nWriteData' ,     "Intervall as multiple of Analyze_dt at which HDF5 files "//&
                                                 !"(e.g. State,TimeAvg,Fluc) are written.",&
                                                 !'1')
!CALL prms%CreateIntOption(    'AnalyzeExactFunc',"Define exact function used for analyze (e.g. for computing L2 errors). "//&
                                                 !"Default: Same as IniExactFunc")
!CALL prms%CreateIntOption(    'AnalyzeRefState' ,"Define state used for analyze (e.g. for computing L2 errors). "//&
                                                 !"Default: Same as IniRefState")
!CALL prms%CreateLogicalOption('doMeasureFlops',  "Set true to measure flop count, if compiled with PAPI.",&
                                                 !'.TRUE.')
!CALL DefineParametersAnalyzeEquation()
#ifdef CODE_ANALYZE
CALL prms%CreateLogicalOption( 'DoCodeAnalyzeOutput' , 'print code analyze info to CodeAnalyze.csv','.TRUE.')
#endif /* CODE_ANALYZE */
#ifndef PARTICLES
CALL prms%CreateIntOption(      'Part-AnalyzeStep'   , 'Analyze is performed each Nth time step','1') 
CALL prms%CreateLogicalOption(  'CalcPotentialEnergy', 'Calculate Potential Energy. Output file is Database.csv','.FALSE.')
#endif
CALL prms%CreateLogicalOption(  'CalcPointsPerWavelength', 'Flag to compute the points per wavelength in each cell','.FALSE.')

CALL prms%SetSection("Analyzefield")
CALL prms%CreateIntOption(    'PoyntingVecInt-Planes', 'Total number of Poynting vector integral planes for measuring the '//&
                                                       'directed power flow (energy flux density: Density and direction of an '//&
                                                       'electromagnetic field.', '0')
CALL prms%CreateRealOption(   'Plane-Tolerance'      , 'Absolute tolerance for checking the Poynting vector integral plane '//&
                                                       'coordinates and normal vectors of the corresponding sides for selecting '//&
                                                       'relevant sides', '1E-5')
CALL prms%CreateRealOption(   'Plane-[$]-x-coord'      , 'TODO-DEFINE-PARAMETER', '0.', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(   'Plane-[$]-y-coord'      , 'TODO-DEFINE-PARAMETER', '0.', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(   'Plane-[$]-z-coord'      , 'TODO-DEFINE-PARAMETER', '0.', numberedmulti=.TRUE.)
CALL prms%CreateRealOption(   'Plane-[$]-factor'       , 'TODO-DEFINE-PARAMETER', '1.', numberedmulti=.TRUE.)
CALL prms%CreateIntOption(    'PoyntingMainDir'        , 'Direction in which the Poynting vector integral is to be measured. '//& 
                                                         '\n1: x \n2: y \n3: z (default)')

END SUBROUTINE DefineParametersAnalyze

SUBROUTINE InitAnalyze()
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Interpolation_Vars    ,ONLY: xGP,wBary,InterpolationInitIsDone
USE MOD_Analyze_Vars          ,ONLY: Nanalyze,AnalyzeInitIsDone,Analyze_dt,DoCalcErrorNorms,CalcPoyntingInt
USE MOD_Analyze_Vars          ,ONLY: CalcPointsPerWavelength,PPWCell
USE MOD_ReadInTools           ,ONLY: GETINT,GETREAL
USE MOD_AnalyzeField          ,ONLY: GetPoyntingIntPlane
USE MOD_ReadInTools           ,ONLY: GETLOGICAL
#ifndef PARTICLES
USE MOD_Particle_Analyze_Vars ,ONLY: PartAnalyzeStep
USE MOD_Analyze_Vars          ,ONLY: doAnalyze,CalcEpot
#endif /*PARTICLES*/
USE MOD_LoadBalance_Vars      ,ONLY: nSkipAnalyze
USE MOD_TimeAverage_Vars      ,ONLY: doCalcTimeAverage
USE MOD_TimeAverage           ,ONLY: InitTimeAverage
USE MOD_IO_HDF5               ,ONLY: AddToElemData,ElementOut
USE MOD_Mesh_Vars             ,ONLY: nElems
USE MOD_Particle_Mesh_Vars    ,ONLY: GEO
#ifdef maxwell
USE MOD_Equation_vars         ,ONLY: Wavelength
#endif /* maxwell */
USE MOD_TimeDisc_Vars         ,ONLY: TEnd
USE MOD_ReadInTools           ,ONLY: PrintOption
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=40)   :: DefStr
INTEGER             :: iElem
REAL                :: PPWCellMax,PPWCellMin
!===================================================================================================================================
IF ((.NOT.InterpolationInitIsDone).OR.AnalyzeInitIsDone) THEN
  CALL abort(&
      __STAMP__&
      ,'InitAnalyse not ready to be called or already called.',999,999.)
  RETURN
END IF
SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)') ' INIT ANALYZE...'

! Get logical for calculating the error norms L2 and LInf
DoCalcErrorNorms = GETLOGICAL('DoCalcErrorNorms' ,'.FALSE.')

! Set the default analyze polynomial degree NAnalyze to 2*(N+1) 
WRITE(DefStr,'(i4)') 2*(PP_N+1)
NAnalyze = GETINT('NAnalyze',DefStr) 
CALL InitAnalyzeBasis(PP_N,NAnalyze,xGP,wBary)

! Get the time step for performing analyzes and integer for skipping certain steps
WRITE(DefStr,WRITEFORMAT) TEnd
Analyze_dt        = GETREAL('Analyze_dt',DefStr)
nSkipAnalyze      = GETINT('nSkipAnalyze','1')
doCalcTimeAverage = GETLOGICAL('CalcTimeAverage'  ,'.FALSE.')
IF(doCalcTimeAverage)  CALL InitTimeAverage()

#ifndef PARTICLES 
PartAnalyzeStep = GETINT('Part-AnalyzeStep','1') 
IF (PartAnalyzeStep.EQ.0) PartAnalyzeStep = 123456789 
DoAnalyze       = .FALSE. 
CalcEpot        = GETLOGICAL('CalcPotentialEnergy','.FALSE.') 
IF(CalcEpot) DoAnalyze = .TRUE. 
#endif /*PARTICLES*/ 

AnalyzeInitIsDone = .TRUE.
SWRITE(UNIT_stdOut,'(A)')' INIT ANALYZE DONE!'
SWRITE(UNIT_StdOut,'(132("-"))')

! init Poynting-Integral
IF(CalcPoyntingInt) CALL GetPoyntingIntPlane()

! Points Per Wavelength
CalcPointsPerWavelength = GETLOGICAL('CalcPointsPerWavelength'  ,'.FALSE.')
IF(CalcPointsPerWavelength)THEN
  ! calculate cell local number excluding neighbor DOFs
  ALLOCATE( PPWCell(1:PP_nElems) )
  PPWCell=0.0
  CALL AddToElemData(ElementOut,'PPWCell',RealArray=PPWCell(1:PP_nElems))
  ! Calculate PPW for each cell
#ifdef maxwell
  CALL PrintOption('Wavelength for PPWCell','OUTPUT',RealOpt=Wavelength)
#else
  CALL PrintOption('Wavelength for PPWCell (fixed to 1.0)','OUTPUT',RealOpt=1.0)
#endif /* maxwell */
  PPWCellMin=HUGE(1.)
  PPWCellMax=-HUGE(1.)
  DO iElem = 1, nElems
#ifdef maxwell
    PPWCell(iElem)     = (REAL(PP_N)+1.)*Wavelength/GEO%CharLength(iElem)
#else
    PPWCell(iElem)     = (REAL(PP_N)+1.)/GEO%CharLength(iElem)
#endif /* maxwell */
    PPWCellMin=MIN(PPWCellMin,PPWCell(iElem))
    PPWCellMax=MAX(PPWCellMax,PPWCell(iElem))
  END DO ! iElem = 1, nElems
#ifdef MPI
  IF(MPIroot)THEN
    CALL MPI_REDUCE(MPI_IN_PLACE , PPWCellMin , 1 , MPI_DOUBLE_PRECISION , MPI_MIN , 0 , MPI_COMM_WORLD , iError)
    CALL MPI_REDUCE(MPI_IN_PLACE , PPWCellMax , 1 , MPI_DOUBLE_PRECISION , MPI_MAX , 0 , MPI_COMM_WORLD , iError)
  ELSE
    CALL MPI_REDUCE(PPWCellMin   , 0          , 1 , MPI_DOUBLE_PRECISION , MPI_MIN , 0 , MPI_COMM_WORLD , iError)
    CALL MPI_REDUCE(PPWCellMax   , 0          , 1 , MPI_DOUBLE_PRECISION , MPI_MAX , 0 , MPI_COMM_WORLD , iError)
    ! in this case the receive value is not relevant. 
  END IF
#endif /*MPI*/
  CALL PrintOption('MIN(PPWCell)','CALCUL.',RealOpt=PPWCellMin)
  CALL PrintOption('MAX(PPWCell)','CALCUL.',RealOpt=PPWCellMax)
END IF
END SUBROUTINE InitAnalyze


SUBROUTINE InitAnalyzeBasis(N_in,Nanalyze_in,xGP,wBary)
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Analyze_Vars, ONLY:wAnalyze,Vdm_GaussN_NAnalyze
USE MOD_Basis,        ONLY: LegendreGaussNodesAndWeights,LegGaussLobNodesAndWeights,BarycentricWeights,InitializeVandermonde
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(IN)                         :: N_in,Nanalyze_in
REAL,INTENT(IN),DIMENSION(0:N_in)          :: xGP,wBary
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL ,DIMENSION(0:Nanalyze_in) :: XiAnalyze
!===================================================================================================================================
  ALLOCATE(wAnalyze(0:NAnalyze_in),Vdm_GaussN_NAnalyze(0:NAnalyze_in,0:N_in))
  CALL LegGaussLobNodesAndWeights(NAnalyze_in,XiAnalyze,wAnalyze)
  CALL InitializeVandermonde(N_in,NAnalyze_in,wBary,xGP,XiAnalyze,Vdm_GaussN_NAnalyze)
END SUBROUTINE InitAnalyzeBasis


SUBROUTINE CalcError(time,L_2_Error)
!===================================================================================================================================
! Calculates L_infinfity and L_2 norms of state variables using the Analyze Framework (GL points+weights)
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_Mesh_Vars          ,ONLY: Elem_xGP,sJ
USE MOD_Equation_Vars      ,ONLY: IniExactFunc
USE MOD_Analyze_Vars       ,ONLY: NAnalyze,Vdm_GaussN_NAnalyze,wAnalyze
USE MOD_DG_Vars            ,ONLY: U
USE MOD_Equation           ,ONLY: ExactFunc
USE MOD_ChangeBasis        ,ONLY: ChangeBasis3D
USE MOD_Particle_Mesh_Vars ,ONLY: GEO
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)               :: time
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(OUT)              :: L_2_Error(PP_nVar)   !< L2 error of the solution
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
INTEGER                       :: iElem,k,l,m
REAL                          :: L_Inf_Error(PP_nVar),U_exact(PP_nVar)
REAL                          :: U_NAnalyze(1:PP_nVar,0:NAnalyze,0:NAnalyze,0:NAnalyze)
REAL                          :: Coords_NAnalyze(3,0:NAnalyze,0:NAnalyze,0:NAnalyze)
REAL                          :: J_NAnalyze(1,0:NAnalyze,0:NAnalyze,0:NAnalyze)
REAL                          :: J_N(1,0:PP_N,0:PP_N,0:PP_N)
REAL                          :: IntegrationWeight
CHARACTER(LEN=40)             :: formatStr
!===================================================================================================================================
L_Inf_Error(:)=-1.E10
L_2_Error(:)=0.
! Interpolate values of Error-Grid from GP's
DO iElem=1,PP_nElems
   ! Interpolate the physical position Elem_xGP to the analyze position, needed for exact function
   CALL ChangeBasis3D(3,PP_N,NAnalyze,Vdm_GaussN_NAnalyze,Elem_xGP(1:3,:,:,:,iElem),Coords_NAnalyze(1:3,:,:,:))
   ! Interpolate the Jacobian to the analyze grid: be carefull we interpolate the inverse of the inverse of the jacobian ;-)
   J_N(1,0:PP_N,0:PP_N,0:PP_N)=1./sJ(:,:,:,iElem)
   CALL ChangeBasis3D(1,PP_N,NAnalyze,Vdm_GaussN_NAnalyze,J_N(1:1,0:PP_N,0:PP_N,0:PP_N),J_NAnalyze(1:1,:,:,:))
   ! Interpolate the solution to the analyze grid
   CALL ChangeBasis3D(PP_nVar,PP_N,NAnalyze,Vdm_GaussN_NAnalyze,U(1:PP_nVar,:,:,:,iElem),U_NAnalyze(1:PP_nVar,:,:,:))
   DO m=0,NAnalyze
     DO l=0,NAnalyze
       DO k=0,NAnalyze
#ifdef PP_HDG
         CALL ExactFunc(IniExactFunc,Coords_NAnalyze(1:3,k,l,m),U_exact,ElemID=iElem)
#else
         CALL ExactFunc(IniExactFunc,time,0,Coords_NAnalyze(1:3,k,l,m),U_exact)
#endif
         L_Inf_Error = MAX(L_Inf_Error,abs(U_NAnalyze(:,k,l,m) - U_exact))
         IntegrationWeight = wAnalyze(k)*wAnalyze(l)*wAnalyze(m)*J_NAnalyze(1,k,l,m)
         ! To sum over the elements, We compute here the square of the L_2 error
         L_2_Error = L_2_Error+(U_NAnalyze(:,k,l,m) - U_exact)*(U_NAnalyze(:,k,l,m) - U_exact)*IntegrationWeight
       END DO ! k
     END DO ! l
   END DO ! m
END DO ! iElem=1,PP_nElems
#ifdef MPI
  IF(MPIroot)THEN
    CALL MPI_REDUCE(MPI_IN_PLACE , L_2_Error   , PP_nVar , MPI_DOUBLE_PRECISION , MPI_SUM , 0 , MPI_COMM_WORLD , iError)
    CALL MPI_REDUCE(MPI_IN_PLACE , L_Inf_Error , PP_nVar , MPI_DOUBLE_PRECISION , MPI_MAX , 0 , MPI_COMM_WORLD , iError)
  ELSE
    CALL MPI_REDUCE(L_2_Error   , 0            , PP_nVar , MPI_DOUBLE_PRECISION , MPI_SUM , 0 , MPI_COMM_WORLD , iError)
    CALL MPI_REDUCE(L_Inf_Error , 0            , PP_nVar , MPI_DOUBLE_PRECISION , MPI_MAX , 0 , MPI_COMM_WORLD , iError)
    ! in this case the receive value is not relevant. 
  END IF
#endif /*MPI*/

! We normalize the L_2 Error with the Volume of the domain and take into account that we have to use the square root
L_2_Error = SQRT(L_2_Error/GEO%MeshVolume)

! Graphical output
IF(MPIroot) THEN
  WRITE(formatStr,'(A5,I1,A7)')'(A13,',PP_nVar,'ES16.7)'
  WRITE(UNIT_StdOut,formatStr)' L_2       : ',L_2_Error
  WRITE(UNIT_StdOut,formatStr)' L_inf     : ',L_Inf_Error
END IF
END SUBROUTINE CalcError

SUBROUTINE AnalyzeToFile(time,CalcTime,L_2_Error)
!===================================================================================================================================
! Writes the L2-error norms to file.
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Analyze_Vars
USE MOD_TimeDisc_Vars ,ONLY:iter
USE MOD_Globals_Vars  ,ONLY:ProjectName
USE MOD_Mesh_Vars    ,ONLY:nGlobalElems
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)                :: time                         ! physical time
REAL,INTENT(IN)                :: CalcTime                     ! computational time
REAL,INTENT(IN)                :: L_2_Error(PP_nVar)           ! L2 error norms
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
!REAL                           :: Dummyreal(PP_nVar+1),Dummytime  ! Dummy values for file handling
INTEGER                        :: openStat! File IO status
CHARACTER(LEN=50)              :: formatStr                    ! format string for the output and Tecplot header
CHARACTER(LEN=30)              :: L2name(PP_nVar)              ! variable name for the Tecplot header
CHARACTER(LEN=300)             :: Filename                     ! Output filename,
!LOGICAL                        :: fileExists                   ! Error handler for file
INTEGER                        :: ioUnit
!===================================================================================================================================
Filename = 'out.'//TRIM(ProjectName)//'.dat'
! Check for file
! INQUIRE(FILE = Filename, EXIST = fileExists) ! now -> FILEEXISTS(Filename)
! FILEEXISTS(Filename)
!! File processing starts here open old and extract information or create new file.
ioUnit=1746 ! This number must be fixed?
  OPEN(UNIT   = ioUnit       ,&
       FILE   = Filename     ,&
       STATUS = 'Unknown'    ,&
       ACCESS = 'SEQUENTIAL' ,&
       IOSTAT = openStat                 )
  IF (openStat.NE.0) THEN
     WRITE(*,*)'ERROR: cannot open Outfile'
  END IF
  ! Create a new file with the Tecplot (ASCII file, not binary) header etc.
  WRITE(ioUnit,*)'TITLE="Analysis,'//TRIM(ProjectName)//'"'
  WRITE(ioUnit,'(A12)')'VARIABLES ='
  ! Fill the formatStr and L2name strings
  CALL getVARformatStr(formatStr,L2name)
  WRITE(ioUnit,formatStr)'"timesteps"',L2name,' "t_sim" "t_CPU" "DOF" "Ncells" "nProcs"'
  WRITE(ioUnit,*) 'ZONE T="Analysis,'//TRIM(ProjectName)//'"'

! Create format string for the variable output
WRITE(formatStr,'(A10,I1,A37)')'(E23.14E5,',PP_nVar,'(1X,E23.14E5),4(1X,E23.14E5),2X,I6.6)'
WRITE(ioUnit,formatstr) REAL(iter),L_2_Error(:),TIME,CalcTime-StartTime, &
                 REAL(nGlobalElems*(PP_N+1)**3),REAL(nGlobalElems),nProcessors

CLOSE(ioUnit) ! outputfile
END SUBROUTINE AnalyzeToFile

SUBROUTINE getVARformatStr(VARformatStr,L2name)
!===================================================================================================================================
! This creates the format string for writeAnalyse2file
!===================================================================================================================================
! MODULES
  USE MOD_Globals
  USE MOD_Equation_Vars,ONLY:StrVarNames
! IMPLICIT VARIABLE HANDLING
  IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
  ! CALC%varName: Name of conservative variables
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
  CHARACTER(LEN=30) :: L2name(PP_nVar) ! The name of the Tecplot variables
  CHARACTER(LEN=50) :: VARformatStr ! L2name format string
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES 
  INTEGER           :: i ! counter
!===================================================================================================================================
DO i=1,PP_nVar
  WRITE(L2name(i),'(A5,A,A2)')' "L2_',TRIM(StrVarNames(i)),'" '
END DO
WRITE(VARformatStr,'(A3)')'(A,'
DO i=1,PP_nVar
  WRITE(VARformatStr,'(A,A1,I2,A1)')TRIM(VARformatStr),'A',LEN_TRIM(L2name(i)),','
END DO
WRITE(VARformatStr,'(A,A2)')TRIM(VARformatStr),'A)'
END SUBROUTINE getVARformatStr

SUBROUTINE FinalizeAnalyze()
!===================================================================================================================================
! Finalizes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Analyze_Vars
USE MOD_AnalyzeField,     ONLY:FinalizePoyntingInt
USE MOD_TimeAverage_Vars, ONLY:doCalcTimeAverage
USE MOD_TimeAverage,      ONLY:FinalizeTimeAverage
! IMPLICIT VARIABLE HANDLINGDGInitIsDone
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
SDEALLOCATE(Vdm_GaussN_NAnalyze)
SDEALLOCATE(wAnalyze)
IF(CalcPoyntingInt) CALL FinalizePoyntingInt()
IF(doCalcTimeAverage) CALL FinalizeTimeAverage
AnalyzeInitIsDone = .FALSE.
END SUBROUTINE FinalizeAnalyze


SUBROUTINE PerformAnalyze(OutputTime,tenddiff,forceAnalyze,OutPut,LastIter_In)
!===================================================================================================================================
! Initializes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Analyze_Vars           ,ONLY: CalcPoyntingInt,DoAnalyze,DoCalcErrorNorms,OutputErrorNorms
USE MOD_Analyze_Vars           ,ONLY: DoSurfModelAnalyze
USE MOD_Restart_Vars           ,ONLY: DoRestart
USE MOD_TimeDisc_Vars          ,ONLY: iter,tEnd
USE MOD_RecordPoints           ,ONLY: RecordPoints
USE MOD_LoadDistribution       ,ONLY: WriteElemTimeStatistics
USE MOD_Globals_Vars           ,ONLY: ProjectName
#ifdef PARTICLES
USE MOD_Mesh_Vars              ,ONLY: MeshFile
USE MOD_TimeDisc_Vars          ,ONLY: dt
USE MOD_Particle_Vars          ,ONLY: WriteMacroVolumeValues,WriteMacroSurfaceValues,MacroValSamplIterNum,PartSurfaceModel
USE MOD_Particle_Analyze       ,ONLY: AnalyzeParticles,CalculatePartElemData
USE MOD_Particle_Analyze_Vars  ,ONLY: PartAnalyzeStep
USE MOD_SurfaceModel_Analyze_Vars,ONLY: SurfaceAnalyzeStep
USE MOD_SurfaceModel_Analyze   ,ONLY: AnalyzeSurface
USE MOD_DSMC_Vars              ,ONLY: DSMC, iter_macvalout,iter_macsurfvalout
USE MOD_DSMC_Vars              ,ONLY: DSMC_HOSolution
USE MOD_Particle_Tracking_vars ,ONLY: ntracks,tTracking,tLocalization,MeasureTrackTime
USE MOD_LD_Analyze             ,ONLY: LD_data_sampling, LD_output_calc
#if !defined(LSERK)
USE MOD_DSMC_Vars              ,ONLY: useDSMC
#endif
#if (PP_TimeDiscMethod!=1000) && (PP_TimeDiscMethod!=1001)
USE MOD_Particle_Vars          ,ONLY: PartSurfaceModel
USE MOD_Particle_Boundary_Vars ,ONLY: AnalyzeSurfCollis, CalcSurfCollis
USE MOD_Particle_Boundary_Vars ,ONLY: SurfMesh, SampWall
USE MOD_DSMC_Analyze           ,ONLY: DSMCHO_data_sampling, WriteDSMCHOToHDF5
USE MOD_DSMC_Analyze           ,ONLY: CalcSurfaceValues
#endif
#if (PP_TimeDiscMethod!=42) && !defined(LSERK)
USE MOD_LD_Vars                ,ONLY: useLD
USE MOD_Particle_Vars          ,ONLY: DelayTime
#endif /*PP_TimeDiscMethod!=42 && !defined(LSERK)*/
#else /* no Particles*/
USE MOD_Particle_Analyze_Vars  ,ONLY: PartAnalyzeStep
USE MOD_AnalyzeField           ,ONLY: AnalyzeField
#endif /*PARTICLES*/
#if (PP_nVar>=6)
USE MOD_AnalyzeField           ,ONLY: CalcPoyntingIntegral
#endif /*PP_nVar>=6*/
#ifdef LSERK
USE MOD_Recordpoints_Vars      ,ONLY: RPSkip
#endif /*LSERK*/
#if defined(LSERK) ||  defined(IMPA) || (PP_TimeDiscMethod==110)
USE MOD_RecordPoints_Vars      ,ONLY: RP_onProc
#endif /*defined(LSERK) ||  defined(IMPA) || (PP_TimeDiscMethod==110)*/
#ifdef CODE_ANALYZE
USE MOD_Particle_Surfaces_Vars ,ONLY: rTotalBBChecks,rTotalBezierClips,SideBoundingBoxVolume,rTotalBezierNewton
#endif /*CODE_ANALYZE*/
#if USE_LOADBALANCE
USE MOD_LoadBalance_tools      ,ONLY: LBStartTime,LBPauseTime
#endif /*USE_LOADBALANCE*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)               :: OutputTime
REAL,INTENT(IN)               :: tenddiff
LOGICAL,INTENT(IN)            :: forceAnalyze,output
LOGICAL,INTENT(IN),OPTIONAL   :: LastIter_In
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
#ifdef PARTICLES
#if (PP_TimeDiscMethod!=1000) && (PP_TimeDiscMethod!=1001)
INTEGER                       :: iSide
#endif
#ifdef MPI
INTEGER                       :: RECI
REAL                          :: RECR
#endif /*MPI*/
#endif /*PARTICLES*/
#ifdef CODE_ANALYZE
REAL                          :: TotalSideBoundingBoxVolume,rDummy
#endif /*CODE_ANALYZE*/
LOGICAL                       :: LastIter
REAL                          :: L_2_Error(PP_nVar)
REAL                          :: CalcTime
#if USE_LOADBALANCE
REAL                          :: tLBStart ! load balance
#endif /*USE_LOADBALANCE*/
!===================================================================================================================================

! Create .csv file for performance analysis and load balance: write header line
CALL WriteElemTimeStatistics(WriteHeader=.TRUE.,iter=iter)

! not for first iteration (when analysis is called within RK steps)
#if (PP_TimeDiscMethod==1)||(PP_TimeDiscMethod==2)||(PP_TimeDiscMethod==6)||(PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506)
IF((iter.EQ.0).AND.(.NOT.forceAnalyze)) RETURN
!IF(iter.EQ.0) RETURN
#endif

LastIter=.FALSE.
IF(PRESENT(LastIter_in))THEN
  IF(LastIter_in) LastIter=.TRUE.
END IF

!----------------------------------------------------------------------------------------------------------------------------------
! DG-Solver
!----------------------------------------------------------------------------------------------------------------------------------

! Calculate error norms
IF(forceAnalyze.OR.Output)THEN
    CalcTime=BOLTZPLATZTIME()
  IF(DoCalcErrorNorms) THEN
    OutputErrorNorms=.TRUE.
    CALL CalcError(OutputTime,L_2_Error)
    IF (OutputTime.GE.tEnd) CALL AnalyzeToFile(OutputTime,CalcTime,L_2_Error)
  END IF
  IF(MPIroot) THEN
    ! write out has to be "Sim time" due to analyzes in reggie. Reggie searches for exactly this tag
    WRITE(UNIT_StdOut,'(A13,ES16.7)')' Sim time  : ',OutputTime
    IF (OutputTime.GT.0.) THEN
      WRITE(UNIT_StdOut,'(132("."))')
      WRITE(UNIT_stdOut,'(A,A,A,F8.2,A)') ' BOLTZPLATZ RUNNING ',TRIM(ProjectName),'... [',CalcTime-StartTime,' sec ]'
      WRITE(UNIT_StdOut,'(132("-"))')
    ELSE
      WRITE(UNIT_StdOut,'(132("="))')
    END IF
  END IF
END IF

! poynting vector
IF (CalcPoyntingInt) THEN
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart) ! Start time measurement
#endif /*USE_LOADBALANCE*/
#if (PP_nVar>=6)
  IF(forceAnalyze .AND. .NOT.DoRestart)THEN
    ! initial analysis is only performed for NO restart
    CALL CalcPoyntingIntegral(OutputTime,doProlong=.TRUE.)
  ELSE
     ! analysis s performed for if iter can be divided by PartAnalyzeStep or for the dtAnalysis steps (writing state files) 
#if defined(LSERK)
    IF(DoRestart)THEN ! for a restart, the analyze should NOT be performed in the first iteration, because it is the zero state
      IF(iter.GT.1)THEN
        ! for LSERK the analysis is performed in the next RK-stage, thus, if a dtAnalysis step is performed, the analysis
        ! is triggered with prolong-to-face, which would else be missing    
        IF(MOD(iter,PartAnalyzeStep).EQ.0 .AND. .NOT. OutPut) CALL CalcPoyntingIntegral(OutputTime,doProlong=.FALSE.)
        IF(MOD(iter,PartAnalyzeStep).NE.0 .AND. OutPut .AND. .NOT.LastIter)  CALL CalcPoyntingIntegral(OutputTime,doProlong=.TRUE.)
      END IF
    ELSE
      ! for LSERK the analysis is performed in the next RK-stage, thus, if a dtAnalysis step is performed, the analysis
      ! is triggered with prolong-to-face, which would else be missing    
      IF(MOD(iter,PartAnalyzeStep).EQ.0 .AND. .NOT. OutPut) CALL CalcPoyntingIntegral(OutputTime,doProlong=.FALSE.)
      IF(MOD(iter,PartAnalyzeStep).NE.0 .AND. OutPut .AND. .NOT.LastIter) CALL CalcPoyntingIntegral(OutputTime,doProlong=.TRUE.)
    END IF
#else
    IF(.NOT.LastIter)THEN
      IF(MOD(iter,PartAnalyzeStep).EQ.0 .AND. .NOT. OutPut) CALL CalcPoyntingIntegral(OutputTime,doProlong=.TRUE.)
      IF(MOD(iter,PartAnalyzeStep).NE.0 .AND. OutPut)       CALL CalcPoyntingIntegral(OutputTime,doProlong=.TRUE.)
    END IF
#endif
  END IF ! ForceAnalyze
#if defined(LSERK)
  ! for LSERK timediscs the analysis is shifted, hence, this last iteration is NOT performed
  IF(LastIter) CALL CalcPoyntingIntegral(OutputTime,doProlong=.TRUE.)
#else
  IF(LastIter .AND.MOD(iter,PartAnalyzeStep).NE.0) CALL CalcPoyntingIntegral(OutputTime,doProlong=.TRUE.)
#endif
#endif
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_DGANALYZE,tLBStart)
#endif /*USE_LOADBALANCE*/
END IF

! fill recordpoints buffer
#if defined(LSERK) || defined(IMPA) || (PP_TimeDiscMethod==110)
IF(RP_onProc) THEN
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart) ! Start time measurement
#endif /*USE_LOADBALANCE*/
#ifdef LSERK
  IF(RPSkip)THEN
    RPSkip=.FALSE.
  ELSE
    CALL RecordPoints(OutputTime,forceAnalyze,Output)
  END IF
#else
  CALL RecordPoints(OutputTime,forceAnalyze,Output)
#endif /*LSERK*/
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_DGANALYZE,tLBStart)
#endif /*USE_LOADBALANCE*/
END IF
#endif

!----------------------------------------------------------------------------------------------------------------------------------
! PIC & DG-Sovler
!----------------------------------------------------------------------------------------------------------------------------------
IF (DoAnalyze.OR.DoSurfModelAnalyze)  THEN
#ifdef PARTICLES 
  ! particle analyze
  IF(forceAnalyze .AND. .NOT.DoRestart)THEN
    ! initial analysis is only performed for NO restart
    CALL AnalyzeParticles(OutputTime)
    CALL AnalyzeSurface(OutputTime)
  ELSE
    ! analysis s performed for if iter can be divided by PartAnalyzeStep or for the dtAnalysis steps (writing state files) 
    IF(DoRestart)THEN ! for a restart, the analyze should NOT be performed in the first iteration, because it is the zero state
#if defined(IMPA) || defined(ROS)
      IF(iter.GE.1)THEN
#else
      IF(iter.GT.1)THEN
#endif
        IF(    (MOD(iter,PartAnalyzeStep).EQ.0 .AND. .NOT. OutPut .AND. .NOT.LastIter) &
           .OR.(MOD(iter,PartAnalyzeStep).NE.0 .AND.       OutPut .AND. .NOT.LastIter))&
           CALL AnalyzeParticles(OutputTime)
        IF(    (MOD(iter,SurfaceAnalyzeStep).EQ.0 .AND. .NOT. OutPut .AND. .NOT.LastIter) &
           .OR.(MOD(iter,SurfaceAnalyzeStep).NE.0 .AND.       OutPut .AND. .NOT.LastIter))&
           CALL AnalyzeSurface(OutputTime)
      END IF
    ELSE
      IF(    (MOD(iter,PartAnalyzeStep).EQ.0 .AND. .NOT. OutPut .AND. .NOT.LastIter) &
         .OR.(MOD(iter,PartAnalyzeStep).NE.0 .AND.       OutPut .AND. .NOT.LastIter))&
         CALL AnalyzeParticles(OutputTime)
      IF(    (MOD(iter,SurfaceAnalyzeStep).EQ.0 .AND. .NOT. OutPut .AND. .NOT.LastIter) &
         .OR.(MOD(iter,SurfaceAnalyzeStep).NE.0 .AND.       OutPut .AND. .NOT.LastIter))&
         CALL AnalyzeSurface(OutputTime)
   END IF
  END IF
#if defined(LSERK)
  ! for LSERK timediscs the analysis is shifted, hence, this last iteration is NOT performed
  IF(LastIter) CALL AnalyzeParticles(OutputTime)
#else
  IF(LastIter .AND.MOD(iter,PartAnalyzeStep).NE.0) CALL AnalyzeParticles(OutputTime)
  IF(LastIter .AND.MOD(iter,SurfaceAnalyzeStep).NE.0) CALL AnalyzeSurface(OutputTime)
#endif
#else /*pure DGSEM */
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart) ! Start time measurement
#endif /*USE_LOADBALANCE*/
  ! analyze field
  IF(forceAnalyze .AND. .NOT.DoRestart)THEN
    ! initial analysis is only performed for NO restart
    CALL AnalyzeField(OutputTime)
  ELSE
    IF(DoRestart)THEN ! for a restart, the analyze should NOT be performed in the first iteration, because it is the zero state
      IF(iter.GT.1)THEN
        ! analysis s performed for if iter can be divided by PartAnalyzeStep or for the dtAnalysis steps (writing state files)
        IF(    (MOD(iter,PartAnalyzeStep).EQ.0 .AND. .NOT. OutPut .AND. .NOT.LastIter) &
           .OR.(MOD(iter,PartAnalyzeStep).NE.0 .AND.       OutPut .AND. .NOT.LastIter))&
           CALL AnalyzeField(OutputTime)
      END IF
    ELSE
      ! analysis s performed for if iter can be divided by PartAnalyzeStep or for the dtAnalysis steps (writing state files)
      IF(    (MOD(iter,PartAnalyzeStep).EQ.0 .AND. .NOT. OutPut .AND. .NOT.LastIter) &
         .OR.(MOD(iter,PartAnalyzeStep).NE.0 .AND.       OutPut .AND. .NOT.LastIter))&
         CALL AnalyzeField(OutputTime)
    END IF
  END IF
#if defined(LSERK)
  ! for LSERK timediscs the analysis is shifted, hence, this last iteration is NOT performed
  IF(LastIter) CALL AnalyzeField(OutputTime)
#else
  IF(LastIter .AND.MOD(iter,PartAnalyzeStep).NE.0) CALL AnalyzeField(OutputTime)
#endif
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_DGANALYZE,tLBStart)
#endif /*USE_LOADBALANCE*/
#endif /*PARTICLES*/
END IF

#ifdef PARTICLES
IF(OutPut .OR. ForceAnalyze) CALL CalculatePartElemData()
#endif /*PARTICLES*/

!----------------------------------------------------------------------------------------------------------------------------------
! DSMC & LD 
!----------------------------------------------------------------------------------------------------------------------------------
! update of time here
#ifdef PARTICLES
#if USE_LOADBALANCE
CALL LBStartTime(tLBStart) ! Start time measurement
#endif /*USE_LOADBALANCE*/

! write volume data for DSMC macroscopic values 
IF ((WriteMacroVolumeValues).AND.(.NOT.Output))THEN
#if (PP_TimeDiscMethod==1000)
  CALL LD_data_sampling()  ! Data sampling for output
#elif(PP_TimeDiscMethod==1001)
  CALL LD_DSMC_data_sampling()
#else
  CALL DSMCHO_data_sampling()
#endif
  IF (iter.GT.0) iter_macvalout = iter_macvalout + 1
  IF (MacroValSamplIterNum.LE.iter_macvalout) THEN
#if (PP_TimeDiscMethod==1000)
    CALL LD_output_calc()  ! Data sampling for output
#elif(PP_TimeDiscMethod==1001)
    CALL LD_DSMC_output_calc()
#else
    CALL WriteDSMCHOToHDF5(TRIM(MeshFile),OutputTime)
#endif
    iter_macvalout = 0
    DSMC%SampNum = 0
    DSMC_HOSolution = 0.0
    IF(DSMC%CalcQualityFactors) THEN
      DSMC%QualityFacSamp(:,:) = 0.
    END IF
  END IF
END IF

! write surface data for DSMC macroscopic values 
IF ((WriteMacroSurfaceValues).AND.(.NOT.Output))THEN
  IF (iter.GT.0) iter_macsurfvalout = iter_macsurfvalout + 1
  IF (MacroValSamplIterNum.LE.iter_macsurfvalout) THEN
#if (PP_TimeDiscMethod!=1000) && (PP_TimeDiscMethod!=1001)
    CALL CalcSurfaceValues
    DO iSide=1,SurfMesh%nTotalSides 
      SampWall(iSide)%State=0.
      IF (PartSurfaceModel.GT.0) THEN
        SampWall(iSide)%Adsorption=0.
        SampWall(iSide)%Accomodation=0.
        SampWall(iSide)%Reaction=0.
      END IF
    END DO
    IF (CalcSurfCollis%AnalyzeSurfCollis) THEN
      AnalyzeSurfCollis%Data=0.
      AnalyzeSurfCollis%Spec=0
      AnalyzeSurfCollis%BCid=0
      AnalyzeSurfCollis%Number=0
      !AnalyzeSurfCollis%Rate=0.
    END IF
#endif
    iter_macsurfvalout = 0
  END IF
END IF

IF(OutPut)THEN
#if (PP_TimeDiscMethod==42)
  IF((dt.EQ.tEndDiff).AND.(useDSMC).AND.(.NOT.DSMC%ReservoirSimu)) THEN
    IF (DSMC%NumOutput.GT.0) THEN
      CALL WriteDSMCHOToHDF5(TRIM(MeshFile),OutputTime)
      IF(DSMC%CalcSurfaceVal) CALL CalcSurfaceValues
    END IF
  END IF
#elif defined(LSERK)
  !additional output after push of final dt (for LSERK output is normally before first stage-push, i.e. actually for previous dt)
  IF(dt.EQ.tEndDiff)THEN
    ! volume data
    IF(WriteMacroVolumeValues)THEN
      iter_macvalout = iter_macvalout + 1
      IF (MacroValSamplIterNum.LE.iter_macvalout) THEN
        CALL WriteDSMCHOToHDF5(TRIM(MeshFile),OutputTime)
        iter_macvalout = 0
        DSMC%SampNum = 0
        DSMC_HOSolution = 0.0
      END IF
    END IF
    ! surface data
    IF (WriteMacroSurfaceValues) THEN
      iter_macsurfvalout = iter_macsurfvalout + 1
      IF (MacroValSamplIterNum.LE.iter_macsurfvalout) THEN
        CALL CalcSurfaceValues
        DO iSide=1,SurfMesh%nTotalSides
          SampWall(iSide)%State=0.
        END DO
        IF (CalcSurfCollis%AnalyzeSurfCollis) THEN
          AnalyzeSurfCollis%Data=0.
          AnalyzeSurfCollis%Spec=0
          AnalyzeSurfCollis%BCid=0
          AnalyzeSurfCollis%Number=0
          !AnalyzeSurfCollis%Rate=0.
        END IF
        iter_macsurfvalout = 0
      END IF
    END IF
  END IF
#else
  IF((dt.EQ.tEndDiff).AND.(useDSMC).AND.(.NOT.WriteMacroVolumeValues).AND.(.NOT.WriteMacroSurfaceValues)) THEN
    IF ((.NOT. useLD).AND.(DSMC%NumOutput.GT.0)) THEN
      CALL WriteDSMCHOToHDF5(TRIM(MeshFile),OutputTime)
    END IF
    IF ((OutputTime.GE.DelayTime).AND.(DSMC%NumOutput.GT.0)) THEN
      IF(DSMC%CalcSurfaceVal) CALL CalcSurfaceValues
    END IF
  END IF
#endif
END IF

! meassure tracking time for particles // no MPI barrier MPI Wall-time but local CPU time
! allows non-synchronous meassurement of particle tracking
IF(OutPut .AND. MeasureTrackTime)THEN
#ifdef MPI
  IF(MPIRoot) THEN
    CALL MPI_REDUCE(MPI_IN_PLACE,nTracks      , 1 ,MPI_INTEGER         ,MPI_SUM,0,MPI_COMM_WORLD,IERROR)
    CALL MPI_REDUCE(MPI_IN_PLACE,tTracking    , 1 ,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,IERROR)
    CALL MPI_REDUCE(MPI_IN_PLACE,tLocalization, 1 ,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,IERROR)
  ELSE ! no Root
    CALL MPI_REDUCE(nTracks      ,RECI,1,MPI_INTEGER         ,MPI_SUM,0,MPI_COMM_WORLD,IERROR)
    CALL MPI_REDUCE(tTracking    ,RECR,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,IERROR)
    CALL MPI_REDUCE(tLocalization,RECR,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD,IERROR)
  END IF
#endif /*MPI*/
  SWRITE(UNIT_StdOut,'(132("-"))')
  SWRITE(UNIT_stdOut,'(A,I15)')   ' Number of trackings:   ',nTracks
  SWRITE(UNIT_stdOut,'(A,F15.6)') ' Tracking time:         ',tTracking
  SWRITE(UNIT_stdOut,'(A,F15.8)') ' Average Tracking time: ',tTracking/REAL(nTracks)
  SWRITE(UNIT_stdOut,'(A,F15.6)') ' Localization time:     ',tLocalization
  SWRITE(UNIT_StdOut,'(132("-"))')
  nTracks=0
  tTracking=0.
  tLocalization=0.
END IF ! only during output like Doftime
#if USE_LOADBALANCE
CALL LBPauseTime(LB_PARTANALYZE,tLBStart)
#endif /*USE_LOADBALANCE*/
#endif /*PARTICLES*/

!----------------------------------------------------------------------------------------------------------------------------------
! Code Analyze
!----------------------------------------------------------------------------------------------------------------------------------

#ifdef CODE_ANALYZE
! particle analyze
IF (DoAnalyze)  THEN
  IF(forceAnalyze)THEN
    CALL CodeAnalyzeOutput(OutputTime)
  ELSE
    IF(MOD(iter,PartAnalyzeStep).EQ.0 .AND. .NOT. OutPut) CALL CodeAnalyzeOutput(OutputTime) 
  END IF
  IF(LastIter)THEN
    CALL CodeAnalyzeOutput(OutputTime) 
    SWRITE(UNIT_stdOut,'(A51)') 'CODE_ANALYZE: Following output has been accumulated'
    SWRITE(UNIT_stdOut,'(A35,E15.7)') ' rTotalBBChecks    : ' , rTotalBBChecks
    SWRITE(UNIT_stdOut,'(A35,E15.7)') ' rTotalBezierClips : ' , rTotalBezierClips
    SWRITE(UNIT_stdOut,'(A35,E15.7)') ' rTotalBezierNewton: ' , rTotalBezierNewton
    TotalSideBoundingBoxVolume=SUM(SideBoundingBoxVolume)
#ifdef MPI
    IF(MPIRoot) THEN
      CALL MPI_REDUCE(MPI_IN_PLACE,TotalSideBoundingBoxVolume , 1 , MPI_DOUBLE_PRECISION, MPI_SUM,0, MPI_COMM_WORLD, IERROR)
    ELSE ! no Root
      CALL MPI_REDUCE(TotalSideBoundingBoxVolume,rDummy  ,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD, IERROR)
    END IF
#endif /* MPI */
    SWRITE(UNIT_stdOut,'(A35,E15.7)') ' Total Volume of SideBoundingBox: ' , TotalSideBoundingBoxVolume
  END IF
END IF
#endif /*CODE_ANALYZE*/

END SUBROUTINE PerformAnalyze

#ifdef CODE_ANALYZE
SUBROUTINE CodeAnalyzeOutput(TIME)
!===================================================================================================================================
! output of code_analyze stuff: costly analyze routines for sanity checks and debugging
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_Analyze_Vars            ,ONLY:DoAnalyze,DoCodeAnalyzeOutput
USE MOD_Particle_Analyze_Vars   ,ONLY:IsRestart
USE MOD_Restart_Vars            ,ONLY:DoRestart
USE MOD_Particle_Surfaces_Vars  ,ONLY:rBoundingBoxChecks,rPerformBezierClip,rTotalBBChecks,rTotalBezierClips,rPerformBezierNewton
USE MOD_Particle_Surfaces_Vars  ,ONLY:rTotalBezierNewton
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
REAL,INTENT(IN)     :: Time
!----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                :: rDummy
LOGICAL             :: isOpen
CHARACTER(LEN=350)  :: outfile
INTEGER             :: unit_index, OutputCounter
!===================================================================================================================================
IF(.NOT.DoCodeAnalyzeOutput) RETURN ! check if the output is to be skipped and return if true

IF ( DoRestart ) THEN
  isRestart = .true.
END IF
IF (DoAnalyze) THEN
  !SWRITE(UNIT_StdOut,'(132("-"))')
  !SWRITE(UNIT_stdOut,'(A)') ' PERFORMING PARTICLE ANALYZE...'
  OutputCounter = 2
  unit_index = 555
#ifdef MPI
  IF(MPIROOT)THEN
#endif    /* MPI */
   INQUIRE(UNIT   = unit_index , OPENED = isOpen)
   IF (.NOT.isOpen) THEN
     outfile = 'CodeAnalyze.csv'
     IF (isRestart .and. FILEEXISTS(outfile)) THEN
        OPEN(unit_index,file=TRIM(outfile),position="APPEND",status="OLD")
        !CALL FLUSH (unit_index)
     ELSE
        OPEN(unit_index,file=TRIM(outfile))
        !CALL FLUSH (unit_index)
        !--- insert header
      
        WRITE(unit_index,'(A6,A5)',ADVANCE='NO') 'TIME', ' '
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,'(I3.3,A11)',ADVANCE='NO') OutputCounter,'-nBBChecks     '
          OutputCounter = OutputCounter + 1
        WRITE(unit_index,'(A1)',ADVANCE='NO') ','
        WRITE(unit_index,'(I3.3,A12)',ADVANCE='NO') OutputCounter,'-nBezierClips   '
          OutputCounter = OutputCounter + 1
        WRITE(unit_index,'(A14)') ' ' 
     END IF
   END IF
#ifdef MPI
  END IF
#endif    /* MPI */
  
 ! MPI Communication
#ifdef MPI
  IF(MPIRoot) THEN
    CALL MPI_REDUCE(MPI_IN_PLACE,rBoundingBoxChecks , 1 , MPI_DOUBLE_PRECISION, MPI_SUM,0, MPI_COMM_WORLD, IERROR)
    CALL MPI_REDUCE(MPI_IN_PLACE,rPerformBezierClip, 1 , MPI_DOUBLE_PRECISION, MPI_SUM,0, MPI_COMM_WORLD, IERROR)
    CALL MPI_REDUCE(MPI_IN_PLACE,rPerformBezierNewton, 1 , MPI_DOUBLE_PRECISION, MPI_SUM,0, MPI_COMM_WORLD, IERROR)
  ELSE ! no Root
    CALL MPI_REDUCE(rBoundingBoxChecks,rDummy  ,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD, IERROR)
    CALL MPI_REDUCE(rPerformBezierClip,rDummy,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD, IERROR)
    CALL MPI_REDUCE(rPerformBezierNewton,rDummy,1,MPI_DOUBLE_PRECISION,MPI_SUM,0,MPI_COMM_WORLD, IERROR)
  END IF
#endif /* MPI */
  
#ifdef MPI
   IF(MPIROOT)THEN
#endif    /* MPI */
     WRITE(unit_index,104,ADVANCE='NO') Time
     WRITE(unit_index,'(A1)',ADVANCE='NO') ','
     WRITE(unit_index,104,ADVANCE='NO') rBoundingBoxChecks
     WRITE(unit_index,'(A1)',ADVANCE='NO') ','
     WRITE(unit_index,104,ADVANCE='NO') rPerformBezierClip
     WRITE(unit_index,'(A1)',ADVANCE='NO') ',' 
     WRITE(unit_index,104,ADVANCE='NO') rPerformBezierNewton
     WRITE(unit_index,'(A1)') ' ' 
#ifdef MPI
   END IF
#endif    /* MPI */
  
104    FORMAT (e25.14)

!SWRITE(UNIT_stdOut,'(A)')' PARTCILE ANALYZE DONE!'
!SWRITE(UNIT_StdOut,'(132("-"))')
ELSE
!SWRITE(UNIT_stdOut,'(A)')' NO PARTCILE ANALYZE TO DO!'
!SWRITE(UNIT_StdOut,'(132("-"))')
END IF ! DoAnalyze

! nullify and save total number
rTotalBBChecks=rTotalBBChecks+REAL(rBoundingBoxChecks,16)
rBoundingBoxChecks=0.
rTotalBezierClips=rTotalBezierClips+REAL(rPerformBezierClip,16)
rPerformBezierClip=0.
rTotalBezierNewton=rTotalBezierNewton+REAL(rPerformBezierNewton,16)
rPerformBezierNewton=0.

END SUBROUTINE CodeAnalyzeOutput
#endif /*CODE_ANALYZE*/

END MODULE MOD_Analyze
