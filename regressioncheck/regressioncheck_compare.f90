#include "boltzplatz.h"

!==================================================================================================================================
!> Contains the routines to 
!> - compare the LNorm norm
!> - compare Datasets of H5-Files
!> - reuired io-routines
!==================================================================================================================================
MODULE MOD_RegressionCheck_Compare
! MODULES
IMPLICIT NONE
PRIVATE
SAVE
!----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------

INTERFACE CompareResults
  MODULE PROCEDURE CompareResults
END INTERFACE

INTERFACE CompareConvergence
  MODULE PROCEDURE CompareConvergence
END INTERFACE

INTERFACE CompareNorm
  MODULE PROCEDURE CompareNorm
END INTERFACE

INTERFACE CompareDataSet
  MODULE PROCEDURE CompareDataSet
END INTERFACE

INTERFACE CompareRuntime
  MODULE PROCEDURE CompareRuntime
END INTERFACE

INTERFACE ReadNorm
  MODULE PROCEDURE ReadNorm
END INTERFACE

PUBLIC::CompareResults,CompareConvergence,CompareNorm,CompareDataSet,CompareRuntime,ReadNorm
!==================================================================================================================================

CONTAINS

!==================================================================================================================================
!> Compare the results that were created by the binary execution
!==================================================================================================================================
SUBROUTINE CompareResults(iExample,iSubExample,MPIthreadsStr)
!===================================================================================================================================
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_RegressionCheck_Tools,   ONLY: AddError
USE MOD_RegressionCheck_Vars,    ONLY: Examples
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(IN)             :: iExample,iSubExample
CHARACTER(LEN=*),INTENT(IN)    :: MPIthreadsStr
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,ALLOCATABLE               :: ReferenceNorm(:,:)                !> L2 and Linf norm of the executed example from a reference
                                                                    !> solution
INTEGER                        :: ErrorStatus                       !> Error-code of regressioncheck
!==================================================================================================================================
! -----------------------------------------------------------------------------------------------------------------------
! compare the results and write error messages for the current case
! -----------------------------------------------------------------------------------------------------------------------
SWRITE(UNIT_stdOut,'(A)',ADVANCE='no')  ' Comparing results...'
! check error norms  L2/LInf
ALLOCATE(ReferenceNorm(Examples(iExample)%nVar,2))
IF(Examples(iExample)%ReferenceNormFile.EQ.'')THEN
  ! constant value, should be zero no reference file given
  CALL CompareNorm(ErrorStatus,iExample,iSubExample)
ELSE
  ! read in reference and compare to reference solution
  CALL ReadNorm(iExample,ReferenceNorm)
  CALL CompareNorm(ErrorStatus,iExample,iSubExample,ReferenceNorm)
END IF
DEALLOCATE(ReferenceNorm)
IF(ErrorStatus.EQ.1)THEN
  SWRITE(UNIT_stdOut,'(A)')   ' Error-norm mismatched! Example failed! '
  SWRITE(UNIT_stdOut,'(A)')   ' For more information: '
  SWRITE(UNIT_stdOut,'(A,A)') ' Out-file: ', TRIM(Examples(iExample)%PATH)//'std.out'
  SWRITE(UNIT_stdOut,'(A,A)') ' Errorfile: ', TRIM(Examples(iExample)%PATH)//'err.out'
  CALL AddError(MPIthreadsStr,'Mismatch of error norms',iExample,iSubExample,ErrorStatus=1,ErrorCode=3)
END IF

! ConvergenceTest
IF(Examples(iExample)%ConvergenceTest)THEN
  IF(iSubExample.EQ.MAX(1,Examples(iExample)%SubExampleNumber))THEN ! after subexample 
    ! the subexample must be executed with "N" or "MeshFile": check if the convergence was successful
    CALL CompareConvergence(iExample)
    IF(Examples(iExample)%ErrorStatus.EQ.3)THEN
      CALL AddError(MPIthreadsStr,'Mismatch Order of '//TRIM(Examples(iExample)%ConvergenceTestType)&
                                                      //'-Convergence',iExample,iSubExample,ErrorStatus=3,ErrorCode=3)
    END IF
  END IF
END IF

! diff h5 file
IF(Examples(iExample)%H5DIFFReferenceStateFile.NE.'')THEN
  CALL CompareDataSet(iExample)
  IF(Examples(iExample)%ErrorStatus.EQ.5)THEN
    CALL AddError(MPIthreadsStr,'h5diff: Comparison not possible',iExample,iSubExample,ErrorStatus=3,ErrorCode=4)
  ELSEIF(Examples(iExample)%ErrorStatus.EQ.3)THEN
    CALL AddError(MPIthreadsStr,'Mismatch in HDF5-files. Datasets are unequal',iExample,iSubExample,ErrorStatus=3,ErrorCode=4)
  END IF
END IF

! Integrate over line
IF(Examples(iExample)%IntegrateLine)THEN
  CALL IntegrateLine(ErrorStatus,iExample)
  IF(Examples(iExample)%ErrorStatus.EQ.5)THEN
    CALL AddError(MPIthreadsStr,'Mismatch in LineIntegral',iExample,iSubExample,ErrorStatus=5,ErrorCode=5)
  END IF
END IF

! read a single row from a file and compare each entry
IF(Examples(iExample)%CompareDatafileRow)THEN
  CALL CompareDatafileRow(ErrorStatus,iExample)
  IF(Examples(iExample)%ErrorStatus.EQ.5)THEN
    CALL AddError(MPIthreadsStr,'Mismatch in CompareDatafileRow',iExample,iSubExample,ErrorStatus=5,ErrorCode=5)
  END IF
END IF

! read an array from a HDF5 file and compare certain entry bounds that must be limited to a supplied value range
IF(Examples(iExample)%CompareHDF5ArrayBounds)THEN
  CALL CompareHDF5ArrayBounds(ErrorStatus,iExample)
  IF(Examples(iExample)%ErrorStatus.EQ.5)THEN
    CALL AddError(MPIthreadsStr,'Mismatch in CompareHDF5ArrayBounds',iExample,iSubExample,ErrorStatus=5,ErrorCode=5)
  END IF
END IF

! successful execution and comparison
IF(Examples(iExample)%ErrorStatus.EQ.0)THEN
  SWRITE(UNIT_stdOut,'(A)')  ' Example successful! '
END IF

END SUBROUTINE CompareResults


!==================================================================================================================================
!> Compare the results that were created by the binary execution
!==================================================================================================================================
SUBROUTINE CompareConvergence(iExample)
!===================================================================================================================================
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_RegressionCheck_Vars,    ONLY: Examples
USE MOD_RegressionCheck_tools,   ONLY: CalcOrder
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(IN)             :: iExample
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                        :: iSTATUS
INTEGER                        :: I,J
INTEGER                        :: NumberOfCellsInteger
INTEGER                        :: iSubExample,p
REAL,ALLOCATABLE               :: Order(:,:),OrderAvg(:)
INTEGER,ALLOCATABLE            :: OrderIncrease(:,:)
LOGICAL,ALLOCATABLE            :: OrderReached(:)
REAL                           :: SuccessRuns,SuccessRate
LOGICAL                        :: DoDebugOutput
!==================================================================================================================================
DoDebugOutput=.TRUE. ! change to ".TRUE." if problems with this routine occur for info written to screen
SWRITE(UNIT_stdOut,'(A)')''
SWRITE(UNIT_stdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)')' ConvergenceTest: '
! 
IF(DoDebugOutput)THEN
  SWRITE(UNIT_stdOut,'(A,I5,A,I5,A)')' L2 Error for nVar=[',Examples(iExample)%nVar,&
                                 '] and SubExampleNumber=[',Examples(iExample)%SubExampleNumber,']'
  SWRITE(UNIT_stdOut,'(A5)', ADVANCE="NO") ''
  DO J=1,Examples(iExample)%nVar
    SWRITE(UNIT_stdOut, '(A10,I3,A1)',ADVANCE="NO") 'nVar=[',J,']'
  END DO
  SWRITE(UNIT_stdOut,'(A)')''
  DO I=1,Examples(iExample)%SubExampleNumber
    SWRITE(UNIT_stdOut,'(I5)', ADVANCE="NO") I
    DO J=1,Examples(iExample)%nVar
        SWRITE(UNIT_stdOut, '(E14.6)',ADVANCE="NO") Examples(iExample)%ConvergenceTestError(I,J)
    END DO
    SWRITE(UNIT_stdOut,'(A)')''
  END DO
  SWRITE(UNIT_stdOut,'(A)')''
END IF

! Calculate the approximate distance between the DG DOF
! -----------------------------------------------------------------------------------------------------------------------
! p-convergence
IF(TRIM(Examples(iExample)%ConvergenceTestType).EQ.'p')THEN
  ! for p-convergence, the number of cells is constant: convert type from CHARACTER to INTEGER
  CALL str2int(ADJUSTL(TRIM(Examples(iExample)%NumberOfCellsStr(1))),NumberOfCellsInteger,iSTATUS) ! NumberOfCellsStr -> Int
  SWRITE(UNIT_stdOut,'(A,I4,A)')' Selecting p-convergence: Number of cells in one direction=[',NumberOfCellsInteger,'] (const.)'
  SWRITE(UNIT_stdOut,'(A)')''
  ! Calculate the approximate distance between the DG DOF
  DO iSubExample=1,Examples(iExample)%SubExampleNumber
    CALL str2int(ADJUSTL(TRIM(Examples(iExample)%SubExampleOption(iSubExample))),p,iSTATUS) ! SubExampleOption -> Int
    Examples(iExample)%ConvergenceTestGridSize(iSubExample)=&
    Examples(iExample)%ConvergenceTestDomainSize/(NumberOfCellsInteger*(p+1))
  END DO
! -----------------------------------------------------------------------------------------------------------------------
! h-convergence
ELSEIF(TRIM(Examples(iExample)%ConvergenceTestType).EQ.'h')THEN
  SWRITE(UNIT_stdOut,'(A,E14.6,A)')&
  ' Selecting h-convergence: Expected Order of Convergence = [',Examples(iExample)%ConvergenceTestValue,']'
  SWRITE(UNIT_stdOut,'(A)')''
  ! Calc the approximate distance between the DG DOF
  DO iSubExample=1,Examples(iExample)%SubExampleNumber
    CALL str2int(ADJUSTL(TRIM(Examples(iExample)%NumberOfCellsStr(iSubExample))) &
                 ,NumberOfCellsInteger,iSTATUS) ! sanity check if the number of threads is correct
    Examples(iExample)%ConvergenceTestGridSize(iSubExample)=&
    Examples(iExample)%ConvergenceTestDomainSize/(NumberOfCellsInteger*(Examples(iExample)%ConvergenceTestValue-1.+1.))
  END DO
END IF
! -----------------------------------------------------------------------------------------------------------------------

! Calculate ConvergenceTestGridSize (average spacing between DOF)
ALLOCATE(Order(Examples(iExample)%SubExampleNumber-1,Examples(iExample)%nVar))
DO J=1,Examples(iExample)%nVar
  DO I=1,Examples(iExample)%SubExampleNumber-1
    CALL CalcOrder(2,Examples(iExample)%ConvergenceTestGridSize(I:I+1),&
                     Examples(iExample)%ConvergenceTestError(   I:I+1,J),Order(I,J))
  END DO
END DO

! Check, if the Order of Convergece is increasing with increasing polynomial degree (only important for p-convergence)
ALLOCATE(OrderIncrease(Examples(iExample)%SubExampleNumber-2,Examples(iExample)%nVar))
DO J=1,Examples(iExample)%nVar
  DO I=1,Examples(iExample)%SubExampleNumber-2
    IF(Order(I,J).LT.Order(I+1,J))THEN ! increasing order
      OrderIncrease(I,J)=1
    ELSE ! non-increasing order
      OrderIncrease(I,J)=0
    END IF
  END DO
END DO

! Calculate the averged Order of Convergence (only important for h-convergence)
ALLOCATE(OrderAvg(Examples(iExample)%nVar))
DO J=1,Examples(iExample)%nVar
  CALL CalcOrder(Examples(iExample)%SubExampleNumber,Examples(iExample)%ConvergenceTestGridSize(:),&
                                                     Examples(iExample)%ConvergenceTestError(:,J),OrderAvg(J))
END DO

! Check the calculated Orders of convergence
ALLOCATE(OrderReached(Examples(iExample)%nVar))
OrderReached=.FALSE. ! default
! -----------------------------------------------------------------------------------------------------------------------
! p-convergence
IF(TRIM(Examples(iExample)%ConvergenceTestType).EQ.'p')THEN
  ! 75% of the calculated values for the order of convergece must be increasing with decreasing grid spacing
  DO J=1,Examples(iExample)%nVar
    IF(REAL(SUM(OrderIncrease(:,J)))/REAL(Examples(iExample)%SubExampleNumber-2).LT.0.75)THEN
      OrderReached(J)=.FALSE.
    ELSE
      OrderReached(J)=.TRUE.
    END IF
  END DO
! -----------------------------------------------------------------------------------------------------------------------
! h-convergence
ELSEIF(TRIM(Examples(iExample)%ConvergenceTestType).EQ.'h')THEN
  ! Check Order of Convergence versus the expected value and tolerance from input
  DO J=1,Examples(iExample)%nVar
OrderReached(J)=ALMOSTEQUALRELATIVE(OrderAvg(J),Examples(iExample)%ConvergenceTestValue,Examples(iExample)%ConvergenceTestTolerance)
     IF((OrderReached(J).EQV..FALSE.).AND.(OrderAvg(J).GT.0.0))THEN
       !IntegralCompare=1
       SWRITE(UNIT_stdOut,'(A)')         ' CompareConvergence does not match! Error in computation!'
       SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' OrderAvg(J)                             = ',OrderAvg(J)
       SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' Examples(iExample)%ConvergenceTestValue = ',Examples(iExample)%ConvergenceTestValue
       SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' Tolerance                               = ',Examples(iExample)%ConvergenceTestTolerance
     END IF
  END DO
END IF


IF(DoDebugOutput)THEN
  ! Write average spacing between DOF
  SWRITE(UNIT_stdOut,'(A)')' ConvergenceTestGridSize (average spacing between DOF)'
  DO I=1,Examples(iExample)%SubExampleNumber
        write(*, '(I5,E14.6)') I,Examples(iExample)%ConvergenceTestGridSize(I)
  END DO
  ! Write Order of convergence
  SWRITE(UNIT_stdOut,'(A)')''
  SWRITE(UNIT_stdOut,'(A,I5,A,I5,A)')' Order of convergence for nVar=[',Examples(iExample)%nVar,&
                                 '] and SubExampleNumber-1=[',Examples(iExample)%SubExampleNumber-1,']'
  SWRITE(UNIT_stdOut,'(A5)', ADVANCE="NO") ''
  DO J=1,Examples(iExample)%nVar
    SWRITE(UNIT_stdOut, '(A10,I3,A1)',ADVANCE="NO") 'nVar=[',J,']'
  END DO
  SWRITE(UNIT_stdOut,'(A)')''
  DO I=1,Examples(iExample)%SubExampleNumber-1
    SWRITE(UNIT_stdOut,'(I5)', ADVANCE="NO") I
    DO J=1,Examples(iExample)%nVar
      SWRITE(UNIT_stdOut,'(E14.6)',ADVANCE="NO") Order(I,J)
    END DO
    SWRITE(UNIT_stdOut,'(A)')''
  END DO
  ! Write averge convergence order
  SWRITE(UNIT_stdOut,'(A5)',ADVANCE="NO")'     '
  DO J=1,Examples(iExample)%nVar
    SWRITE(UNIT_stdOut, '(A14)',ADVANCE="NO") ' -------------'
  END DO
  SWRITE(UNIT_stdOut,'(A)')''
  SWRITE(UNIT_stdOut,'(A5)',ADVANCE="NO")'mean'
  DO J=1,Examples(iExample)%nVar
    SWRITE(UNIT_stdOut,'(E14.6)',ADVANCE="NO") OrderAvg(J)
  END DO
  SWRITE(UNIT_stdOut,'(A)')''
  SWRITE(UNIT_stdOut,'(A)')''
  !    ! Write increasing order
  !    DO I=1,Examples(iExample)%SubExampleNumber-2
  !      SWRITE(UNIT_stdOut,'(I5)', ADVANCE="NO") I
  !      DO J=1,Examples(iExample)%nVar
  !        SWRITE(UNIT_stdOut,'(I14)',ADVANCE="NO") OrderIncrease(I,J)
  !      END DO
  !      SWRITE(UNIT_stdOut,'(A)')''
  !    END DO
  !    SWRITE(UNIT_stdOut,'(A)')''

  ! Write if order of convergence was reached (h- or p-convergence)
  SWRITE(UNIT_stdOut,'(A5)',ADVANCE="NO")'Check'
  DO J=1,Examples(iExample)%nVar
    SWRITE(UNIT_stdOut,'(L14)',ADVANCE="NO") OrderReached(J)
  END DO
  SWRITE(UNIT_stdOut,'(A)')''
  SWRITE(UNIT_stdOut,'(132("-"))')
END IF

! The Success Rate (default if 50%) of nVar Convergence tests must succeed
SuccessRuns=0.
DO J=1,Examples(iExample)%nVar
  IF(OrderReached(J))SuccessRuns=SuccessRuns+1.
END DO
SuccessRate=SuccessRuns/REAL(Examples(iExample)%nVar)
IF((SuccessRate.GT.Examples(iExample)%ConvergenceTestSuccessRate).OR.&
   (ALMOSTEQUALRELATIVE(SuccessRate,Examples(iExample)%ConvergenceTestSuccessRate,1e-3)))THEN
  Examples(iExample)%ErrorStatus=0
  SWRITE(UNIT_stdOut,'(A)')' Convergence successful ...'
ELSE
  Examples(iExample)%ErrorStatus=3
  SWRITE(UNIT_stdOut,'(A)')' Failed convergence test because the success rate could no be met'
END IF
SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' Success Rate = ',SuccessRate
SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' Tolerance    = ',Examples(iExample)%ConvergenceTestSuccessRate

END SUBROUTINE CompareConvergence


!==================================================================================================================================
!> Compare the runtime of an example  || fixed to a specific system
!> simply extract the regressioncheck settings from the parameter_reggie.ini
!> Not yet implemented!
!==================================================================================================================================
SUBROUTINE CompareRuntime()
! MODULES
USE MOD_Globals
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!==================================================================================================================================


END SUBROUTINE CompareRuntime


!==================================================================================================================================
!> Compares the L2- and LInf-Norm of an example with a reference-norm. The reference-norm is given as a constant or from a 
!> reference simulation (previous simulation.)
!> To compare the norms, the std.out file of the simulation is read-in. The last L2- and LInf-norm in the std.out file are
!> compared to the reference.
!==================================================================================================================================
SUBROUTINE CompareNorm(LNormCompare,iExample,iSubExample,ReferenceNorm)
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_StringTools,           ONLY: STRICMP
USE MOD_RegressionCheck_Vars,  ONLY: Examples
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(IN)           :: iExample,iSubExample
REAL,INTENT(IN),OPTIONAL     :: ReferenceNorm(Examples(iExample)%nVar,2)
INTEGER,INTENT(OUT)          :: LNormCompare
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                      :: iSTATUS2,iSTATUS,iVar
INTEGER                      :: ioUnit
CHARACTER(LEN=255)           :: FileName,temp1,temp2,temp3
LOGICAL                      :: ExistFile,L2Compare,LInfCompare,L2Found,LInfFound
REAL                         :: LNorm(Examples(iExample)%nVar),L2(Examples(iExample)%nVar),LInf(Examples(iExample)%nVar)
REAL                         :: eps
!==================================================================================================================================

! get fileID and open file
FileName=TRIM(Examples(iExample)%PATH)//'std.out'
INQUIRE(File=FileName,EXIST=ExistFile)
IF(.NOT.ExistFile) THEN
  SWRITE(UNIT_stdOut,'(A,A)') ' CompareNorm: no File found under ',TRIM(Examples(iExample)%PATH)
  SWRITE(UNIT_stdOut,'(A,A)') ' FileName:                  ','std.out'
  SWRITE(UNIT_stdOut,'(A,L)') ' ExistFile:                 ',ExistFile
  ERROR STOP 1
ELSE
  OPEN(NEWUNIT=ioUnit,FILE=TRIM(FileName),STATUS='OLD',IOSTAT=iSTATUS,ACTION='READ') 
END IF

! find the last L2 and LInf norm the std.out file of the example
LNorm=-1.
L2Compare=.TRUE.
LInfCompare=.TRUE.
LNormCompare=1
L2Found=.FALSE.
LInfFound=.FALSE.
DO 
  READ(ioUnit,'(A)',IOSTAT=iSTATUS) temp1!,temp2,LNorm(1),LNorm(2),LNorm(3),LNorm(4),LNorm(5)
  IF(iSTATUS.EQ.-1) EXIT ! End Of File (EOF) reached: exit the loop
  
  READ(temp1,*,IOSTAT=iSTATUS2) temp2,temp3,LNorm
  IF(STRICMP(temp2,'L_2')) THEN
    L2=LNorm
    L2Found=.TRUE.
  END IF
  IF(STRICMP(temp2,'L_inf')) THEN
    LInf=LNorm
    LInfFound=.TRUE.
  END IF
END DO
! close the file
CLOSE(ioUnit)

! check if L_2 or L_inf was found in *.out file
IF(.NOT.L2Found)THEN
  L2=0.
END IF
IF(.NOT.LInfFound)THEN
  LInf=0.
END IF

! when NaN is encountered set the values to HUGE
IF(ANY(ISNAN(L2)))   L2  =HUGE(1.)
IF(ANY(ISNAN(LInf))) LInf=HUGE(1.)

! Save values for ConvergenceTest
IF(Examples(iExample)%ConvergenceTest)THEN
  Examples(iExample)%ConvergenceTestError(iSubExample,1:Examples(iExample)%nVar)=L2(1:Examples(iExample)%nVar)
END IF

! compare the retrieved norms from the std.out file
IF(PRESENT(ReferenceNorm))THEN ! use user-defined norm if present, else use 0.001*SQRT(PP_RealTolerance)
  ! compare with reference file
  IF(Examples(iExample)%ReferenceTolerance.GT.0.)THEN
    eps=Examples(iExample)%ReferenceTolerance
  ELSE
    eps=0.001*SQRT(PP_RealTolerance)
  END IF
  DO iVar=1,Examples(iExample)%nVar
    IF(.NOT.ALMOSTEQUALRELATIVE(L2(iVar),ReferenceNorm(iVar,1),eps))THEN
      L2Compare=.FALSE.
      SWRITE(UNIT_stdOut,'(A)') ''
      SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' L2Norm                =',L2(iVar)
      SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' ReferenceNorm(iVar,1) =',ReferenceNorm(iVar,1)
      SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' eps (tolerance)       =',eps
      RETURN ! fail
    END IF
  END DO ! iVar=1,Examples(iExample)%nVar
  DO iVar=1,Examples(iExample)%nVar
    IF(.NOT.ALMOSTEQUALRELATIVE(LInf(iVar),ReferenceNorm(iVar,2),eps))THEN
      LInfCompare=.FALSE.
      SWRITE(UNIT_stdOut,'(A)') ''
      SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' LInfNorm              =',LInf(iVar)
      SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' ReferenceNorm(iVar,1) =',ReferenceNorm(iVar,2)
      SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' eps (tolerance)       =',eps
      RETURN ! fail
    END IF
  END DO ! iVar=1,Examples(iExample)%nVar
ELSE ! use user-defined norm if present, else use 100.*PP_RealTolerance
  ! compare with single value
  IF(Examples(iExample)%ReferenceTolerance.GT.0.)THEN
    eps=Examples(iExample)%ReferenceTolerance
  ELSE
    eps=1000*PP_RealTolerance ! instead of 100, use 1000 because ketchesonrk4-20 with flexi failes here
  END IF
  IF(ANY(L2.GT.eps))THEN
    L2Compare=.FALSE.
    SWRITE(UNIT_stdOut,'(A)') ''
    SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' L2Norm                =',MAXVAL(L2)
    SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' eps (tolerance)       =',eps
    RETURN ! fail
  END IF
  IF(ANY(LInf.GT.eps))THEN
    LInfCompare=.FALSE.
    SWRITE(UNIT_stdOut,'(A)') ''
    SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' LInfNorm              =',MAXVAL(LInf)
    SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' eps (tolerance)       =',eps
    RETURN ! fail
  END IF
END IF
IF(L2Compare.AND.LInfCompare)LNormCompare=0

END SUBROUTINE CompareNorm


!==================================================================================================================================
!> Read in the error norms (L2,Linf) from a given reference computation and reference norm file
!> The reference files contains only the L2 and Linf norm for each variable of the reference computation.
!==================================================================================================================================
SUBROUTINE ReadNorm(iExample,ReferenceNorm)
! MODULES
USE MOD_Globals
USE MOD_RegressionCheck_Vars,  ONLY: Examples
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(IN)                   :: iExample
REAL,INTENT(OUT)                     :: ReferenceNorm(Examples(iExample)%nVar,2)
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                              :: iSTATUS2,iSTATUS
INTEGER                              :: ioUnit
CHARACTER(LEN=255)                   :: FileName,temp1,temp2,temp3

LOGICAL                              :: ExistFile
REAL                                 :: LNorm(Examples(iExample)%nVar)
!==================================================================================================================================
! open file and read in
FileName=TRIM(Examples(iExample)%PATH)//TRIM(Examples(iExample)%ReferenceNormFile)
INQUIRE(File=FileName,EXIST=ExistFile)
IF(.NOT.ExistFile) THEN
  SWRITE(UNIT_stdOut,'(A,A)') ' ReadNorm: no File found under ',TRIM(Examples(iExample)%PATH)
  SWRITE(UNIT_stdOut,'(A,A)') ' FileName:                     ',TRIM(Examples(iExample)%ReferenceNormFile)
  SWRITE(UNIT_stdOut,'(A,L)') ' ExistFile:                    ',ExistFile
  ERROR STOP 1
ELSE
  OPEN(NEWUNIT=ioUnit,FILE=TRIM(FileName),STATUS='OLD',IOSTAT=iSTATUS,ACTION='READ') 
END IF

! read in the norms
DO 
  READ(ioUnit,'(A)',IOSTAT=iSTATUS) temp1!,temp2,LNorm(1),LNorm(2),LNorm(3),LNorm(4),LNorm(5)
  IF(iSTATUS.EQ.-1) EXIT
  
  READ(temp1,*,IOSTAT=iSTATUS2) temp2,temp3,LNorm
  IF(TRIM(temp2).EQ.'L_2') THEN
    ReferenceNorm(1:Examples(iExample)%nVar,1)=LNorm
  END IF
  IF(TRIM(temp2).EQ.'L_Inf') THEN
    ReferenceNorm(1:Examples(iExample)%nVar,2)=LNorm
  END IF
END DO
CLOSE(ioUnit)

END SUBROUTINE ReadNorm


!==================================================================================================================================
!> Compares dataset of two different h5 files
!> It uses the reference and check-state-file information as well as the dataset information from the parameter_reggie.ini
!> The two datasets in the two different files are compared by a system-call to h5diff. If h5diff finds a difference, the
!> return status of the systemcall  is >0. Additionally, a absolute tolerance is used to allow for deviation of the datasets due to
!> different compilers.
!> This routine can compare all given datasets by their name, it is not restricted to the dg_solution. Thus it can be applied to 
!> all h5-files. Attention: This subroutine requires h5diff in the path of the used shell.
!==================================================================================================================================
SUBROUTINE CompareDataSet(iExample)
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_RegressionCheck_Vars,  ONLY: Examples
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(IN)             :: iExample
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255)             :: DataSet,tmp
CHARACTER(LEN=999)             :: CheckedFileName,OutputFileName,OutputFileName2,ReferenceStateFile,SYSCOMMAND
CHARACTER(LEN=25)              :: tmpTol,tmpInt
INTEGER                        :: iSTATUS,iSTATUS2,ioUnit,I
LOGICAL                        :: ExistCheckedFile,ExistReferenceNormFile,ExistFile
!==================================================================================================================================
OutputFileName     = ''
OutputFileName2    = ''
CheckedFilename    = TRIM(Examples(iExample)%PATH)//TRIM(Examples(iExample)%H5DIFFCheckedStateFile)
ReferenceStateFile = TRIM(Examples(iExample)%PATH)//TRIM(Examples(iExample)%H5DIFFReferenceStateFile)
INQUIRE(File=CheckedFilename,EXIST=ExistCheckedFile)
IF(.NOT.ExistCheckedFile) THEN
  SWRITE(UNIT_stdOut,'(A,A)')  ' h5diff: generated state file does not exist! need ',CheckedFilename
  Examples(iExample)%ErrorStatus=5
  RETURN
END IF
INQUIRE(File=ReferenceStateFile,EXIST=ExistReferenceNormFile)
IF(.NOT.ExistReferenceNormFile) THEN
  SWRITE(UNIT_stdOut,'(A,A)')  ' h5diff: reference state file does not exist! need ',ReferenceStateFile
  Examples(iExample)%ErrorStatus=5
  RETURN
END IF

DataSet=TRIM(Examples(iExample)%H5DIFFReferenceDataSetName)
OutputFileName=TRIM(Examples(iExample)%PATH)//'H5DIFF_info.out'

IF(Examples(iExample)%H5diffTolerance.GT.0.0)THEN
  WRITE(tmpTol,'(E25.14E3)') Examples(iExample)%H5diffTolerance
ELSE
  WRITE(tmpTol,'(E25.14E3)') SQRT(PP_RealTolerance)
END IF
IF(Examples(iExample)%H5diffToleranceType.EQ.'absolute')THEN
  SYSCOMMAND=H5DIFF//' -r --delta='//ADJUSTL(TRIM(tmpTol))//' '//TRIM(ReferenceStateFile)//' ' &
            //TRIM(CheckedFileName)//' /'//TRIM(DataSet)//' /'//TRIM(DataSet)//' > '//TRIM(OutputFileName)
ELSEIF(Examples(iExample)%H5diffToleranceType.EQ.'relative')THEN
  SYSCOMMAND=H5DIFF//' -r --relative='//ADJUSTL(TRIM(tmpTol))//' '//TRIM(ReferenceStateFile)//' ' &
            //TRIM(CheckedFileName)//' /'//TRIM(DataSet)//' /'//TRIM(DataSet)//' > '//TRIM(OutputFileName)
ELSE ! wrong tolerance type
  CALL abort(&
  __STAMP__&
  ,'H5Diff: wrong tolerance type (need "absolute" or "relative")')
END IF
!SWRITE(UNIT_stdOut,'(A)')' SYSCOMMAND: ['//TRIM(SYSCOMMAND)//']'
CALL EXECUTE_COMMAND_LINE(SYSCOMMAND, WAIT=.TRUE., EXITSTAT=iSTATUS)

! check h5diff output (even if iSTATUS==0 it may sitll ahve failed to compare the datasets)
INQUIRE(File=OutputFileName,EXIST=ExistFile)
IF(ExistFile) THEN
  SWRITE(UNIT_stdOut,'(A)')''
  ! read H5DIFF_info.out | list of info
  OPEN(NEWUNIT = ioUnit, FILE = OutputFileName, STATUS ="OLD", IOSTAT = iSTATUS2 ) 
  SWRITE(UNIT_stdOut,'(A)')' Reading '//TRIM(OutputFileName)
  I=0
  DO 
    READ(ioUnit,FMT='(A)',IOSTAT=iSTATUS2) tmp
    IF (iSTATUS2.NE.0) EXIT
    I=I+1
    IF(I.LE.20)THEN
      SWRITE(UNIT_stdOut,'(A)')'      ['//TRIM(tmp)//']'
    END IF
    IF(TRIM(tmp).EQ.'Some objects are not comparable')THEN
      iSTATUS=-5
    END IF
  END DO
  CLOSE(ioUnit)
  IF(I.GT.20)THEN
    I=MIN(I-20,20)
    WRITE(tmpInt,'(I6)') I
    SWRITE(UNIT_stdOut,'(A)')'      ... leaving out intermediate data ...'
    OutputFileName2=TRIM(OutputFileName)//'2'
    SYSCOMMAND='tail -n '//ADJUSTL(TRIM(tmpInt))//' '//TRIM(OutputFileName)//' > '//TRIM(OutputFileName2)
    CALL EXECUTE_COMMAND_LINE(SYSCOMMAND, WAIT=.TRUE., EXITSTAT=iSTATUS2)
    INQUIRE(File=TRIM(OutputFileName2),EXIST=ExistFile)
    IF(ExistFile) THEN
      ! read H5DIFF_info.out | list of info
      OPEN(NEWUNIT = ioUnit, FILE = TRIM(OutputFileName2), STATUS ="OLD", IOSTAT = iSTATUS2 ) 
      DO
        READ(ioUnit,FMT='(A)',IOSTAT=iSTATUS2) tmp
        IF (iSTATUS2.NE.0) EXIT
        SWRITE(UNIT_stdOut,'(A)')'      ['//TRIM(tmp)//']'
      END DO
      CLOSE(ioUnit)
    END IF
  END IF
  SYSCOMMAND='rm '//TRIM(OutputFileName)//' '//TRIM(OutputFileName2)//' > /dev/null 2>&1'
  CALL EXECUTE_COMMAND_LINE(SYSCOMMAND, WAIT=.TRUE., EXITSTAT=iSTATUS2)
ELSE
  SWRITE(UNIT_stdOut,'(A)')' H5DIFF_info.out was not created!'
END IF

! set ErrorStatus
IF(iSTATUS.EQ.0)THEN
  RETURN ! all is safe
ELSEIF(iSTATUS.EQ.-5)THEN
  SWRITE(UNIT_stdOut,'(A)')  ' h5diff: arrays in h5-files have different ranks.'
  Examples(iExample)%ErrorStatus=5
ELSEIF(iSTATUS.EQ.2)THEN
  SWRITE(UNIT_stdOut,'(A)')  ' h5diff: file to compare not found.'
  Examples(iExample)%ErrorStatus=5
ELSEIF(iSTATUS.EQ.127)THEN
  SWRITE(UNIT_stdOut,'(A)')  ' h5diff executable could not be found.'
  Examples(iExample)%ErrorStatus=5
ELSE!IF(iSTATUS.NE.0) THEN
  SWRITE(UNIT_stdOut,'(A)')  ' HDF5 Datasets do not match! Error in computation!'
  SWRITE(UNIT_stdOut,'(A)')  '    Type               : '//ADJUSTL(TRIM(Examples(iExample)%H5diffToleranceType))
  SWRITE(UNIT_stdOut,'(A)')  '    tmpTol             : '//ADJUSTL(TRIM(tmpTol))
  SWRITE(UNIT_stdOut,'(A)')  '    H5DIFF             : '//ADJUSTL(TRIM(H5DIFF))
  SWRITE(UNIT_stdOut,'(A)')  '    ReferenceStateFile : '//TRIM(Examples(iExample)%H5DIFFReferenceStateFile)
  SWRITE(UNIT_stdOut,'(A)')  '    CheckedFileName    : '//TRIM(Examples(iExample)%H5DIFFCheckedStateFile)
  Examples(iExample)%ErrorStatus=3
END IF

END SUBROUTINE CompareDataSet


!==================================================================================================================================
!> Read column number data from a file and integrates the values numerically
!==================================================================================================================================
SUBROUTINE IntegrateLine(IntegralCompare,iExample)
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_RegressionCheck_Vars,  ONLY: Examples
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(IN)             :: iExample
INTEGER,INTENT(OUT)            :: IntegralCompare
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=1)               :: Delimiter
CHARACTER(LEN=255)             :: FileName
CHARACTER(LEN=355)             :: temp1,temp2
INTEGER                        :: iSTATUS,ioUnit,LineNumbers,I,HeaderLines,j,IndMax,CurrentColumn,IndNum,MaxColumn!,K
INTEGER                        :: IndFirstA,IndLastA,IndFirstB,IndLastB,EOL,MaxRow
LOGICAL                        :: ExistFile,IndexNotFound,IntegralValuesAreEqual
REAL,ALLOCATABLE               :: Values(:,:)
REAL                           :: dx,dQ,Q
!==================================================================================================================================
! check if output file with data for integration over line exists
Filename=TRIM(Examples(iExample)%PATH)//TRIM(Examples(iExample)%IntegrateLineFile)
INQUIRE(File=Filename,EXIST=ExistFile)
IF(.NOT.ExistFile) THEN
  SWRITE(UNIT_stdOut,'(A,A)')  ' IntegrateLine: reference state file does not exist! need ',TRIM(Filename)
  Examples(iExample)%ErrorStatus=5
  RETURN
ELSE
  OPEN(NEWUNIT=ioUnit,FILE=TRIM(FileName),STATUS='OLD',IOSTAT=iSTATUS,ACTION='READ') 
END IF
! init parameters for reading the data file
HeaderLines=Examples(iExample)%IntegrateLineHeaderLines
!HeaderLines=1
Delimiter=ADJUSTL(TRIM(Examples(iExample)%IntegrateLineDelimiter))
MaxColumn=MAXVAL(Examples(iExample)%IntegrateLineRange)
IndMax  =LEN(temp1) ! complete string length
IndFirstA=1
IndLastA =IndMax
IndFirstB=1
IndLastB =IndMax
IndexNotFound=.TRUE.
CurrentColumn=0
EOL=0
DO I=1,2 ! read the file twice in Order to determine the array size
  LineNumbers=0
  DO 
    READ(ioUnit,'(A)',IOSTAT=iSTATUS) temp1 ! get first line assuming it is something like 'nVar= 5'
    IF(iSTATUS.EQ.-1) EXIT ! end of file (EOF) reached
    IF(INDEX(temp1,'!').GT.0)temp1=temp1(1:INDEX(temp1,'!')-1) ! if temp1 contains a '!', remove it and the following characters
    LineNumbers=LineNumbers+1
    IF(I.EQ.2)THEN ! read the data on second round reading the file (in first round, collect the file length by checking each line)
      IF(LineNumbers.GT.HeaderLines)THEN ! remove header lines
        IF(IndexNotFound)THEN
            !temp2=ADJUSTL(TRIM(temp1))  ! don't use ADJUSTL because it cuts away the spaces left to the first column
            temp2=TRIM(temp1)
          ! get index range
          DO J=1,MaxColumn
            IndNum=INDEX(TRIM(temp2),Delimiter)
            IF(IndNum.EQ.1)THEN ! still is same column!!!
              DO ! while IndNum.EQ.1
                IndNum=IndNum+INDEX(TRIM(temp2(IndNum+1:IndMax)),Delimiter)
                IF(IndNum.LE.0)EXIT ! not found - exit
                IF(IndNum.GT.1)EXIT
             END DO ! while
            END IF !IndNum.EQ.1
            IF(IndNum.GT.0)THEN
              CurrentColumn=CurrentColumn+IndNum
              ! first index
              IF(J.EQ.Examples(iExample)%IntegrateLineRange(1)-1)IndFirstA=CurrentColumn+1
              IF(J.EQ.Examples(iExample)%IntegrateLineRange(2)-1)IndFirstB=CurrentColumn+1
              ! last index
              IF(J.EQ.Examples(iExample)%IntegrateLineRange(1))IndLastA=CurrentColumn-1
              IF(J.EQ.Examples(iExample)%IntegrateLineRange(2))IndLastB=CurrentColumn-1
            ELSE
              EOL=EOL+1
              IF(EOL.GT.1)THEN
                SWRITE(UNIT_stdOut,'(A)')  ' IntegrateLines failed to read data! Error in computation!'
                SWRITE(UNIT_stdOut,'(A)')  ' The chosen column for line integration is larger than the available ones!'
                Examples(iExample)%ErrorStatus=5
                ERROR STOP 1
                RETURN
              END IF!IF(EOL.GT.1)
            END IF!IF(IndNum.GT.0)
            temp2=TRIM(temp1(CurrentColumn+1:IndMax))
          END DO!J=1,MaxColumn
        IndexNotFound=.FALSE.
        END IF ! IndexNotFound
        CALL str2real(temp1(IndFirstA:IndLastA),Values(LineNumbers-HeaderLines,1),iSTATUS) 
        CALL str2real(temp1(IndFirstB:IndLastB),Values(LineNumbers-HeaderLines,2),iSTATUS) 
      END IF!IF(LineNumbers.GT.HeaderLines)
    END IF!IF(I.EQ.2)
  END DO ! DO [WHILE]
  IF(I.EQ.1)REWIND(ioUnit)
  IF(I.EQ.2)CLOSE(ioUnit)
  IF(I.EQ.1)MaxRow=LineNumbers-HeaderLines
  IF(I.EQ.1)ALLOCATE(Values(MaxRow,MaxColumn))
  If(I.EQ.1)Values=0.
!       !!!!!!!!!!!!!!!!!!!!!!!!!!!!!
         !print*,shape(Values)
         !IF(I.EQ.2)THEN
           !DO J=1,MaxRow
             !DO K=1,2
                 !write(*,'(E25.14E3,A)', ADVANCE = 'NO') Values(J,K),'  '
               !IF(K.EQ.2)print*,''
             !END DO
           !END DO
         !END IF
         !read*
!       !!!!!!!!!!!!!!!!!!!!!!!!!!!!!
END DO

! integrate the values numerically
Q=0.
DO I=1,MaxRow-1
  ! use trapezoidal rule (also known as the trapezoid rule or trapezium rule)
  dx = Values(I+1,1)-Values(I,1)
  dQ = dx * (Values(I+1,2)+Values(I,2))/2.
  IF(TRIM(Examples(iExample)%IntegrateLineOption).EQ.'DivideByTimeStep')THEN ! assume that the first column is the time!
    IF(ABS(dx).GT.0.0)THEN ! dx is assumed to be dt
      dQ = dQ / dx
    END IF
  END IF
  Q  = Q + dQ
END DO

Q=Q*Examples(iExample)%IntegrateLineMultiplier ! use multiplier if needed

IntegralValuesAreEqual=ALMOSTEQUALRELATIVE(Q,Examples(iExample)%IntegrateLineValue,Examples(iExample)%IntegrateLineTolerance)

IF(.NOT.IntegralValuesAreEqual)THEN
  IntegralCompare=1
  SWRITE(UNIT_stdOut,'(A)')           ' IntegrateLines do not match! Error in computation!'
  SWRITE(UNIT_stdOut,'(A)')           ' IntegrateLineOption                   = '//TRIM(Examples(iExample)%IntegrateLineOption)
  SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' IntegrateLineValue                    = ',Q
  SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' Examples(iExample)%IntegrateLineValue = ',Examples(iExample)%IntegrateLineValue
  IF(ABS(Examples(iExample)%IntegrateLineValue).GT.0.0)THEN
    SWRITE(UNIT_stdOut,'(A,E25.14E3)')' relative Error                        = ',ABS(Q/Examples(iExample)%IntegrateLineValue-1)
  ELSE
    SWRITE(UNIT_stdOut,'(A,E25.14E3)')' absolute Error (compare with 0)       = ',ABS(Q)
  END IF
  SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' Tolerance                             = ',Examples(iExample)%IntegrateLineTolerance
  !SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' 0.1*SQRT(PP_RealTolerance)            = ',0.1*SQRT(PP_RealTolerance)
  Examples(iExample)%ErrorStatus=5
ELSE
  IntegralCompare=0
END IF

END SUBROUTINE IntegrateLine


!==================================================================================================================================
!> Read column number data from a file and integrates the values numerically
!==================================================================================================================================
SUBROUTINE CompareDatafileRow(DataCompare,iExample)
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_RegressionCheck_Vars,  ONLY: Examples
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(IN)             :: iExample
INTEGER,INTENT(OUT)            :: DataCompare
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=1)               :: Delimiter
CHARACTER(LEN=255)             :: FileName
CHARACTER(LEN=255),ALLOCATABLE :: ColumnHeaders(:)
CHARACTER(LEN=10000)           :: temp1,temp2
INTEGER                        :: iSTATUS,ioUnit,LineNumbers,HeaderLines,j
INTEGER                        :: K,ColumnNumber
LOGICAL                        :: ExistFile,ReadHeaderLine,RowFound
LOGICAL,ALLOCATABLE            :: ValuesAreEqual(:)
REAL,ALLOCATABLE               :: Values(:),ValuesRef(:)
INTEGER                        :: DimValues,DimValuesRef,DimColumnHeaders
!==================================================================================================================================
RowFound=.FALSE.
DO K=1,2 ! open the data and reference file
  ! check if output file with data for integration over line exists
  SELECT CASE(K)
  CASE(1) ! reference data file
    Filename=TRIM(Examples(iExample)%PATH)//TRIM(Examples(iExample)%CompareDatafileRowRefFile)
    ReadHeaderLine=Examples(iExample)%CompareDatafileRowReadHeader
  CASE(2) ! newly created data file
    Filename=TRIM(Examples(iExample)%PATH)//TRIM(Examples(iExample)%CompareDatafileRowFile)
    ReadHeaderLine=.FALSE.
  END SELECT
  INQUIRE(File=Filename,EXIST=ExistFile)
  IF(.NOT.ExistFile) THEN
    SWRITE(UNIT_stdOut,'(A,A)')  ' CompareDatafileRow: reference state file does not exist! need ',TRIM(Filename)
    Examples(iExample)%ErrorStatus=5
    RETURN
  ELSE
    OPEN(NEWUNIT=ioUnit,FILE=TRIM(FileName),STATUS='OLD',IOSTAT=iSTATUS,ACTION='READ') 
  END IF
  ! init parameters for reading the data file
  HeaderLines=Examples(iExample)%CompareDatafileRowHeaderLines
  IF(HeaderLines.GE.Examples(iExample)%CompareDatafileRowNumber)CALL abort(&
    __STAMP__&
    ,'CompareDatafileRow: The number of header lines exceeds the number of the row for comparison!')
  Delimiter=ADJUSTL(TRIM(Examples(iExample)%CompareDatafileRowDelimiter))
  LineNumbers=0
  DO 
    READ(ioUnit,'(A)',IOSTAT=iSTATUS) temp1
    IF(iSTATUS.EQ.-1) EXIT ! end of file (EOF) reached
    temp2=ADJUSTL(temp1)
    IF(INDEX(temp2,'!').GT.0)temp2=TRIM(temp2(1:INDEX(temp2,'!')-1)) ! if temp2 contains a '!', 
                                                                     ! remove it and the following characters
    LineNumbers=LineNumbers+1
    IF((LineNumbers.EQ.1).AND.(ReadHeaderLine))THEN
      ColumnNumber=0
      CALL GetColumns(temp2,Delimiter,ColumnString=ColumnHeaders,Column=ColumnNumber)
    ELSEIF(LineNumbers.EQ.Examples(iExample)%CompareDatafileRowNumber)THEN ! remove header lines
      RowFound=.TRUE.
      EXIT
    END IF!IF(LineNumbers.GT.HeaderLines)
  END DO ! DO [WHILE]

  IF(ADJUSTL(TRIM(temp2)).NE.'')THEN ! if string is not empty
    SELECT CASE(K)
    CASE(1) ! reference data file
      CALL GetColumns(temp2,Delimiter,ColumnReal=ValuesRef,Column=ColumnNumber)
    CASE(2) ! newly created data file
      CALL GetColumns(temp2,Delimiter,ColumnReal=Values   ,Column=ColumnNumber)
    END SELECT
  END IF
  CLOSE(ioUnit)
END DO ! K=1,2


DimValues=SIZE(Values)
DimValuesRef=SIZE(ValuesRef)
IF(DimValues.NE.DimValuesRef)THEN ! dimensions of ref values and data file values is different
  SWRITE(UNIT_stdOut,'(A,A)')&
    ' CompareDatafileRow: reference and datafile vector "ValuesRef" and "Values" have different dimensions!' 
  Examples(iExample)%ErrorStatus=5
  RETURN
END IF
IF(ALLOCATED(ColumnHeaders).EQV..TRUE.)THEN
  DimColumnHeaders=SIZE(ColumnHeaders)
  IF(DimValues.NE.DimColumnHeaders)THEN
    SWRITE(UNIT_stdOut,'(A,A)')&
      ' CompareDatafileRow: Header line vector "ColumnHeaders" (1st line in ref file) and "Values" have different dimensions!' 
    Examples(iExample)%ErrorStatus=5
    RETURN
  END IF
ELSE
  ALLOCATE(ColumnHeaders(1:DimValues))
  ColumnHeaders='no header found'
END IF
SWRITE(UNIT_stdOut,'(A)') ""
IF(ColumnNumber.GT.0)THEN
  ALLOCATE(ValuesAreEqual(1:ColumnNumber))
  ValuesAreEqual=.FALSE.
  SWRITE(UNIT_stdOut,'(A)') ''
  DO J=1,ColumnNumber
    ValuesAreEqual(J)=ALMOSTEQUALRELATIVE(Values(J),ValuesRef(J),Examples(iExample)%CompareDatafileRowTolerance)
    IF((ABS(ValuesRef(J)).LE.0.0).OR.(ABS(Values(J)).LE.0.0))THEN ! if the one value is zero -> absolute comparison with tolerance
      IF(MAX(ABS(ValuesRef(J)),ABS(Values(J))).LT.Examples(iExample)%CompareDatafileRowTolerance)ValuesAreEqual(J)=.TRUE.
    END IF
    IF(ValuesAreEqual(J).EQV..FALSE.)THEN
      SWRITE(UNIT_stdOut,'(A)')             ' CompareDatafileRows mismatch for ['//TRIM(ColumnHeaders(J))//']'
      SWRITE(UNIT_stdOut,'(A,E25.14E3)')      ' Value in Reference              = ',ValuesRef(J)
      SWRITE(UNIT_stdOut,'(A,E25.14E3)')      ' Value in data file              = ',Values(J)
      SWRITE(UNIT_stdOut,'(A,E25.14E3)')      ' Tolerance                       = ',Examples(iExample)%CompareDatafileRowTolerance
      IF(ABS(ValuesRef(J)).GT.0.0)THEN
        SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' relative Error                  = ',ABS(Values(J)/ValuesRef(J)-1)
      ELSE
        SWRITE(UNIT_stdOut,'(A,E25.14E3)')  ' absolute Error (compare with 0) = ',ABS(Values(J))
      END IF
      SWRITE(UNIT_stdOut,'(A)') ''
    END IF
  END DO
END IF
IF(ANY(.NOT.ValuesAreEqual))THEN
  DataCompare=1
  SWRITE(UNIT_stdOut,'(A)')         ' CompareDatafileRows do not match! Error in computation!'
  Examples(iExample)%ErrorStatus=5
ELSE
  DataCompare=0
END IF
END SUBROUTINE CompareDatafileRow


!==================================================================================================================================
!> Read column data from the supplied string variable "InputString"
!==================================================================================================================================
SUBROUTINE GetColumns(InputString,Delimiter,ColumnString,ColumnReal,Column)
! MODULES
USE MOD_Globals
USE MOD_Preproc
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(INOUT),OPTIONAL                         :: Column
CHARACTER(LEN=*),INTENT(INOUT)                      :: InputString
CHARACTER(LEN=*),ALLOCATABLE,INTENT(INOUT),OPTIONAL :: ColumnString(:)
REAL,ALLOCATABLE,INTENT(INOUT),OPTIONAL             :: ColumnReal(:)
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255),ALLOCATABLE :: ColumnStringLocal(:)
CHARACTER(LEN=1)               :: Delimiter
INTEGER                        :: IndNumOld,ColumnNumber
INTEGER                        :: iSTATUS,j,IndNum
LOGICAL                        :: InquireColumns
!==================================================================================================================================
IndNumOld=0
IF(PRESENT(Column))THEN
  IF(Column.GT.0)THEN
    ! the number of columns in the string is pre-defined
    ColumnNumber=Column
    InquireColumns=.FALSE.
  ELSE
    InquireColumns=.TRUE.
  END IF
ELSE
  InquireColumns=.TRUE.
END IF
IF(InquireColumns)THEN
  ColumnNumber=1
  ! inquire the number of columns in the string
  IndNum=0
  DO ! while IndNum.EQ.1
    IndNum=IndNum+INDEX(TRIM(InputString(IndNum+1:LEN(InputString))),Delimiter)
    IF(IndNum.LE.0)EXIT ! not found - exit
    IF(IndNumOld.EQ.IndNum)EXIT ! EOL reached - exit
    IndNumOld=IndNum
    ColumnNumber=ColumnNumber+1
  END DO ! while
END IF
IF(PRESENT(Column))Column=ColumnNumber
IF(ADJUSTL(TRIM(InputString)).EQ.'')ColumnNumber=0 ! if InputString is empty, no ColumnNumber information can be extracted
IF(ColumnNumber.GT.0)THEN
  ALLOCATE(ColumnStringLocal(ColumnNumber))
  ColumnStringLocal='' ! default
  IndNum=0
  DO J=1,ColumnNumber
    IndNum=INDEX(TRIM(InputString(1:LEN(InputString))),Delimiter) ! for columns 1 to ColumnNumber-1
    IF(J.EQ.ColumnNumber)IndNum=LEN(InputString)-1          ! for the last ColumnNumber
    IF(IndNum.GT.0)THEN
      ColumnStringLocal(J)=ADJUSTL(TRIM(InputString(1:IndNum-1)))
      InputString=InputString(IndNum+1:LEN(InputString))
    END IF
  END DO
END IF

IF(PRESENT(ColumnString))THEN
  ALLOCATE(ColumnString(ColumnNumber))
  ColumnString='' ! default
  DO J=1,ColumnNumber
    ColumnString(J)=ADJUSTL(TRIM(ColumnStringLocal(J)))
  END DO
  RETURN
END IF
IF(PRESENT(ColumnReal))THEN
  ALLOCATE(ColumnReal(ColumnNumber))
  ColumnReal=0 ! default
  DO J=1,ColumnNumber
    CALL str2real(ColumnStringLocal(J),ColumnReal(J),iSTATUS) 
  END DO
  RETURN
END IF
END SUBROUTINE GetColumns


!==================================================================================================================================
!> Read data from a HDF5 array and compare the array entries with pre-defined boundaries
!==================================================================================================================================
SUBROUTINE CompareHDF5ArrayBounds(ArrayCompare,iExample)
! MODULES
USE MOD_Globals
USE MOD_Preproc
USE MOD_RegressionCheck_Vars,  ONLY: Examples
USE MOD_HDF5_input,            ONLY: OpenDataFile,CloseDataFile,ReadArray,ReadAttribute
USE MOD_HDF5_Input,            ONLY: DatasetExists,File_ID,GetDataSize
USE MOD_IO_HDF5,               ONLY: HSize
IMPLICIT NONE
!----------------------------------------------------------------------------------------------------------------------------------
! INPUT/OUTPUT VARIABLES
INTEGER,INTENT(IN)             :: iExample
INTEGER,INTENT(OUT)            :: ArrayCompare
!----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255)             :: FileName
INTEGER                        :: iSTATUS,ioUnit,ArrayRank,nVal,nSize,I,J
!INTEGER(HSIZE_T)               :: IntSize
LOGICAL                        :: ExistFile,HDF5DatasetExists,FirstFound
!REAL                           :: HDF5DataArray(10000,6)
REAL,ALLOCATABLE               :: HDF5DataArray(:,:)
!==================================================================================================================================
ArrayCompare=0     ! 0 means success
FirstFound=.FALSE. ! first problematic array entry found

!print*,"test"
!SWRITE(UNIT_stdOut,'(A,E25.14,A)') &
!'Example%CompareHDF5ArrayBoundsValue(1) : ',Examples(iExample)%CompareHDF5ArrayBoundsValue(1),' (lower)'
!SWRITE(UNIT_stdOut,'(A,E25.14,A)') &
!'Example%CompareHDF5ArrayBoundsValue(2) : ',Examples(iExample)%CompareHDF5ArrayBoundsValue(2),' (upper)'
!SWRITE(UNIT_stdOut,'(A,I6,A)')     &
!'Example%CompareHDF5ArrayBoundsRange(1) : ',Examples(iExample)%CompareHDF5ArrayBoundsRange(1),' (lower)'
!SWRITE(UNIT_stdOut,'(A,I6,A)')     &
!'Example%CompareHDF5ArrayBoundsRange(2) : ',Examples(iExample)%CompareHDF5ArrayBoundsRange(2),' (upper)'
!SWRITE(UNIT_stdOut,'(A,A)')        'Example%CompareHDF5ArrayBoundsName     :      ',Examples(iExample)%CompareHDF5ArrayBoundsName
!SWRITE(UNIT_stdOut,'(A,A)')        'Example%CompareHDF5ArrayBoundsFile     :      ',Examples(iExample)%CompareHDF5ArrayBoundsFile



Filename=TRIM(Examples(iExample)%PATH)//TRIM(Examples(iExample)%CompareHDF5ArrayBoundsFile)
INQUIRE(File=Filename,EXIST=ExistFile)
IF(.NOT.ExistFile) THEN
  SWRITE(UNIT_stdOut,'(A,A)')  ' CompareHDF5ArrayBoundsFile: reference state file does not exist! need ',TRIM(Filename)
  Examples(iExample)%ErrorStatus=5
  RETURN
ELSE
  OPEN(NEWUNIT=ioUnit,FILE=TRIM(FileName),STATUS='OLD',IOSTAT=iSTATUS,ACTION='READ') 
END IF

!!SWRITE(UNIT_stdOut,*)'Reading [',TRIM(Examples(iExample)%CompareHDF5ArrayBoundsName),'] from File:',TRIM(FileName)
#ifdef MPI
  CALL OpenDataFile(FileName,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.)
#else
  CALL OpenDataFile(FileName,create=.FALSE.,readOnly=.TRUE.)
#endif

CALL DatasetExists(File_ID,TRIM(Examples(iExample)%CompareHDF5ArrayBoundsName),HDF5DatasetExists)
IF(.NOT.HDF5DatasetExists) THEN
  SWRITE(UNIT_stdOut,'(A,A,A1)')  ' CompareHDF5ArrayBoundsFile: Dataset in file does not exist! [',&
                               TRIM(Examples(iExample)%CompareHDF5ArrayBoundsName),"]"
  Examples(iExample)%ErrorStatus=5
  CALL CloseDataFile() 
  RETURN
END IF

! get array dimensions
CALL GetDataSize(File_ID,TRIM(Examples(iExample)%CompareHDF5ArrayBoundsName),ArrayRank,HSize)
!print*,"ArrayRank=",ArrayRank
!print*,"HSize   =",HSize
nVal   = INT(HSize(1))
nSize  = INT(HSize(2))
!print*,"nVal =",nVal
!print*,"nSize=",nSize
IF(ArrayRank.GT.2)THEN
  SWRITE(UNIT_stdOut,'(A,A,A1)')  &
    ' CompareHDF5ArrayBoundsFile: Dataset too large dimension (more than 2 dimensions not implemeted)! [',&
    TRIM(Examples(iExample)%CompareHDF5ArrayBoundsName),"]"
  Examples(iExample)%ErrorStatus=5
  CALL CloseDataFile() 
  RETURN
END IF

! allocate array and read hdf5 file into the array
ALLOCATE(HDF5DataArray(nVal,nSize))
!print*,shape(HDF5DataArray)
!print*,""
!print*,TRIM(Examples(iExample)%CompareHDF5ArrayBoundsName)
!CALL DatasetExists(File_ID,TRIM(Examples(iExample)%CompareHDF5ArrayBoundsName),HDF5DatasetExists)
!print*,"HDF5DatasetExists)=",HDF5DatasetExists
!CALL ReadArray('PartData',2,(/nVal,nSize/),0,1,RealArray=HDF5DataArray)
CALL ReadArray(TRIM(Examples(iExample)%CompareHDF5ArrayBoundsName),2,(/nVal,nSize/),0,1,RealArray=HDF5DataArray)

!read*
!print*,HDF5DataArray
DO I=1,nVal
  DO J=Examples(iExample)%CompareHDF5ArrayBoundsRange(1),Examples(iExample)%CompareHDF5ArrayBoundsRange(2)
    IF( (HDF5DataArray(I,J).LT.Examples(iExample)%CompareHDF5ArrayBoundsValue(1)).OR.&
        (HDF5DataArray(I,J).GT.Examples(iExample)%CompareHDF5ArrayBoundsValue(2))     )THEN
      ArrayCompare=ArrayCompare+1
      IF(FirstFound.EQV..FALSE.)THEN
        SWRITE(UNIT_stdOut,'(A,I10,A1)')' First value outsite range found for [#',ArrayCompare,']'
        SWRITE(UNIT_stdOut,'(A,E25.14)')'     HDF5DataArray(I,J)                     : ',HDF5DataArray(I,J)
        SWRITE(UNIT_stdOut,'(A,E25.14,A)') &
          '     Example%CompareHDF5ArrayBoundsValue(1) : ',Examples(iExample)%CompareHDF5ArrayBoundsValue(1),' (lower)'
        SWRITE(UNIT_stdOut,'(A,E25.14,A)') &
          '     Example%CompareHDF5ArrayBoundsValue(2) : ',Examples(iExample)%CompareHDF5ArrayBoundsValue(2),' (upper)'
        FirstFound=.TRUE.
      END IF
      !print*,HDF5DataArray(I,1:nSize)
      !read*
    END IF
  END DO
END DO

CALL CloseDataFile() 
SDEALLOCATE(HDF5DataArray)

IF(ArrayCompare.GT.0)THEN
  SWRITE(UNIT_stdOut,'(A)')         ' CompareHDF5ArrayBounds do not match! Error in computation!'
  SWRITE(UNIT_stdOut,'(A,I10,A1)')  ' Number of failed comparisons: [',ArrayCompare,']'
  Examples(iExample)%ErrorStatus=5
END IF

END SUBROUTINE CompareHDF5ArrayBounds


END MODULE MOD_RegressionCheck_Compare
