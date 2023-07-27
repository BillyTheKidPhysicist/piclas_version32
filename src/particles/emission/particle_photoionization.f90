!==================================================================================================================================
! Copyright (c) 2023 boltzplatz - numerical plasma dynamics GmbH
!
! This file is part of PICLas (piclas.boltzplatz.eu/piclas/piclas). PICLas is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3
! of the License, or (at your option) any later version.
!
! PICLas is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with PICLas. If not, see <http://www.gnu.org/licenses/>.
!==================================================================================================================================
#include "piclas.h"

MODULE MOD_Particle_Photoionization
!===================================================================================================================================
!> Module for particle insertion through photo-ionization
!===================================================================================================================================
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
PUBLIC :: PhotoIonization_RayTracing_SEE, PhotoIonization_RayTracing_Volume
!===================================================================================================================================
CONTAINS

SUBROUTINE PhotoIonization_RayTracing_SEE()
!===================================================================================================================================
!> Routine calculates the number of secondary electrons to be emitted and inserts them on the surface, utilizing the cell-local
!> photon energy from the raytracing
!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Globals_Vars            ,ONLY: PI
USE MOD_Timedisc_Vars           ,ONLY: dt,time
USE MOD_Particle_Boundary_Vars  ,ONLY: nSurfSample, Partbound, SurfSide2GlobalSide, DoBoundaryParticleOutputHDF5
USE MOD_Particle_Vars           ,ONLY: Species, PartState, usevMPF
USE MOD_RayTracing_Vars         ,ONLY: Ray,UseRayTracing
USE MOD_part_emission_tools     ,ONLY: CalcPhotonEnergy
USE MOD_Particle_Mesh_Vars      ,ONLY: SideInfo_Shared,UseBezierControlPoints
USE MOD_Particle_Surfaces_Vars  ,ONLY: BezierControlPoints3D, BezierSampleXi
USE MOD_Particle_Surfaces       ,ONLY: EvaluateBezierPolynomialAndGradient, CalcNormAndTangBezier
USE MOD_Mesh_Vars               ,ONLY: NGeo
USE MOD_part_emission_tools     ,ONLY: CalcVelocity_FromWorkFuncSEE
USE MOD_Particle_Boundary_Tools ,ONLY: StoreBoundaryParticleProperties
USE MOD_part_operations         ,ONLY: CreateParticle
#ifdef LSERK
USE MOD_Timedisc_Vars           ,ONLY: iStage, RK_c, nRKStages
#endif
#if USE_MPI
USE MOD_Particle_Boundary_Vars  ,ONLY: nComputeNodeSurfTotalSides
USE MOD_Photon_TrackingVars     ,ONLY: PhotonSampWall_Shared
USE MOD_MPI_Shared_Vars         ,ONLY: nComputeNodeProcessors,myComputeNodeRank
#else
USE MOD_Photon_TrackingVars     ,ONLY: PhotonSampWall
USE MOD_Particle_Boundary_Vars  ,ONLY: nSurfTotalSides
#endif /*USE_MPI*/
#if USE_HDG
USE MOD_HDG_Vars                ,ONLY: UseFPC,FPC,UseEPC,EPC
USE MOD_Mesh_Vars               ,ONLY: BoundaryType
#endif /*USE_HDG*/
USE MOD_SurfaceModel_Analyze_Vars ,ONLY: SEE,CalcElectronSEE
!----------------------------------------------------------------------------------------------------------------------------------!
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                  :: t_1, t_2, E_Intensity
INTEGER               :: NbrOfRepetitions, firstSide, lastSide, SideID, iSample, GlobElemID, PartID
INTEGER               :: iSurfSide, p, q, BCID, SpecID, iPart, NbrOfSEE, iSEEBC
REAL                  :: RealNbrOfSEE, TimeScalingFactor, MPF
REAL                  :: Particle_pos(1:3), xi(2)
REAL                  :: RandVal, RandVal2(2), xiab(1:2,1:2), nVec(3), tang1(3), tang2(3), Velo3D(3)
#if USE_HDG
INTEGER               :: iBC,iUniqueFPCBC,iUniqueEPCBC,BCState
#endif /*USE_HDG*/
!===================================================================================================================================
! Check if ray tracing based SEE is active
! 1) Boundary from which rays are emitted
IF(.NOT.UseRayTracing) RETURN
! 2) SEE yield for any BC greater than zero
IF(.NOT.ANY(PartBound%PhotonSEEYield(:).GT.0.)) RETURN

! TODO: Copied here from InitParticleMesh, which is only build if not TriaSurfaceFlux
IF(UseBezierControlPoints)THEN
  IF(.NOT.ALLOCATED(BezierSampleXi)) ALLOCATE(BezierSampleXi(0:nSurfSample))
  DO iSample=0,nSurfSample
    BezierSampleXi(iSample)=-1.+2.0/nSurfSample*iSample
  END DO
END IF

! Surf sides are shared, array calculation can be distributed
#if USE_MPI
firstSide = INT(REAL( myComputeNodeRank   )*REAL(nComputeNodeSurfTotalSides)/REAL(nComputeNodeProcessors))+1
lastSide  = INT(REAL((myComputeNodeRank+1))*REAL(nComputeNodeSurfTotalSides)/REAL(nComputeNodeProcessors))
#else
firstSide = 1
lastSide  = nSurfTotalSides
#endif /*USE_MPI*/

ASSOCIATE( tau         => Ray%PulseDuration      ,&
           tShift      => Ray%tShift             ,&
           lambda      => Ray%WaveLength         ,&
           Period      => Ray%Period)
! Temporal bound of integration
#ifdef LSERK
IF (iStage.EQ.1) THEN
t_1 = Time
t_2 = Time + RK_c(2) * dt
ELSE
  IF (iStage.NE.nRKStages) THEN
    t_1 = Time + RK_c(iStage) * dt
    t_2 = Time + RK_c(iStage+1) * dt
  ELSE
    t_1 = Time + RK_c(iStage) * dt
    t_2 = Time + dt
  END IF
END IF
#else
t_1 = Time
t_2 = Time + dt
#endif

! Calculate the current pulse
NbrOfRepetitions = INT(Time/Period)

! Add arbitrary time shift (-4 sigma_t) so that I_max is not at t=0s
! Note that sigma_t = tau / sqrt(2)
t_1 = t_1 - tShift - NbrOfRepetitions * Period
t_2 = t_2 - tShift - NbrOfRepetitions * Period

! check if t_2 is outside of the pulse
IF(t_2.GT.2.0*tShift) t_2 = 2.0*tShift

TimeScalingFactor = 0.5 * SQRT(PI) * tau * (ERF(t_2/tau)-ERF(t_1/tau))

DO iSurfSide = firstSide, lastSide
  SideID = SurfSide2GlobalSide(SURF_SIDEID,iSurfSide)
  ! TODO: Skip sides which are not mine in the MPI case
  BCID = PartBound%MapToPartBC(SideInfo_Shared(SIDE_BCID,SideID))
  ! Skip non-reflective BC sides
  IF(PartBound%TargetBoundCond(BCID).NE.PartBound%ReflectiveBC) CYCLE
  ! Skip BC sides with zero yield
  IF(PartBound%PhotonSEEYield(BCID).LE.0.) CYCLE
  ! Determine which species is to be inserted
  SpecID = PartBound%PhotonSEEElectronSpecies(BCID)
  ! Sanity check
  IF(SpecID.EQ.0)THEN
    IPWRITE(UNIT_StdOut,*) "BCID =", BCID
    IPWRITE(UNIT_StdOut,*) "PartBound%PhotonSEEElectronSpecies(BCID) =", PartBound%PhotonSEEElectronSpecies(BCID)
    CALL abort(__STAMP__,'Electron species index cannot be zero!')
  END IF ! SpecID.eq.0
  ! Determine which element the particles are going to be inserted
  GlobElemID = SideInfo_Shared(SIDE_ELEMID ,SideID)
  ! Determine the weighting factor of the electron species
  IF(usevMPF)THEN
    MPF = PartBound%PhotonSEEMacroParticleFactor(BCID) ! Use SEE-specific MPF
  ELSE
    MPF = Species(SpecID)%MacroParticleFactor ! Use species MPF
  END IF ! usevMPF
  ! Loop over the subsides
  DO p = 1, nSurfSample
    DO q = 1, nSurfSample
      ! Calculate the number of SEEs per subside
#if USE_MPI
      E_Intensity = PhotonSampWall_Shared(2,p,q,iSurfSide) * TimeScalingFactor
#else
      E_Intensity = PhotonSampWall(2,p,q,iSurfSide) * TimeScalingFactor
#endif /*USE_MPI*/
      RealNbrOfSEE = E_Intensity / CalcPhotonEnergy(lambda) * PartBound%PhotonSEEYield(BCID) / MPF
      CALL RANDOM_NUMBER(RandVal)
      NbrOfSEE = INT(RealNbrOfSEE+RandVal)
      ! Check if photon SEE electric current is to be measured
      IF((NbrOfSEE.GT.0).AND.(CalcElectronSEE))THEN
        ! Note that the negative value of the charge -q is used below
        iSEEBC = SEE%BCIDToSEEBCID(BCID)
        SEE%RealElectronOut(iSEEBC) = SEE%RealElectronOut(iSEEBC) - MPF*NbrOfSEE*Species(SpecID)%ChargeIC
      END IF ! (NbrOfSEE.GT.0).AND.(CalcElectronSEE)
      ! Calculate the normal & tangential vectors
      IF(UseBezierControlPoints)THEN
        ! Use Bezier polynomial
        xi(1)=(BezierSampleXi(p-1)+BezierSampleXi(p))/2. ! (a+b)/2
        xi(2)=(BezierSampleXi(q-1)+BezierSampleXi(q))/2. ! (a+b)/2
        xiab(1,1:2)=(/BezierSampleXi(p-1),BezierSampleXi(p)/)
        xiab(2,1:2)=(/BezierSampleXi(q-1),BezierSampleXi(q)/)
        CALL CalcNormAndTangBezier(nVec,tang1,tang2,xi(1),xi(2),SideID)
      ELSE
        ! Sanity check
        CALL abort(__STAMP__,'Photoionization with ray tracing requires BezierControlPoints3D')
      END IF ! nSurfSample.GT.1
      ! Normal vector provided by the routine points outside of the domain
      nVec = -nVec
      ! Loop over number of particles to be inserted
      DO iPart = 1, NbrOfSEE
        ! Determine particle position within the sub-side
        CALL RANDOM_NUMBER(RandVal2)
        IF(UseBezierControlPoints)THEN
          ! Use Bezier polynomial
          xi=(xiab(:,2)-xiab(:,1))*RandVal2+xiab(:,1)
          CALL EvaluateBezierPolynomialAndGradient(xi,NGeo,3,BezierControlPoints3D(1:3,0:NGeo,0:NGeo,SideID),Point=Particle_pos(1:3))
        ELSE
          ! Sanity check
          CALL abort(__STAMP__,'Photoionization with ray tracing requires BezierControlPoints3D')
        END IF ! nSurfSample.GT.1
        ! Determine particle velocity
        CALL CalcVelocity_FromWorkFuncSEE(PartBound%PhotonSEEWorkFunction(BCID), Species(SpecID)%MassIC, tang1, nVec, Velo3D)
        ! Create new particle
        CALL CreateParticle(SpecID,Particle_pos(1:3),GlobElemID,Velo3D(1:3),0.,0.,0.,NewPartID=PartID,NewMPF=MPF)
        ! 1. Store the particle information in PartStateBoundary.h5
        IF(DoBoundaryParticleOutputHDF5) THEN
          CALL StoreBoundaryParticleProperties(PartID,SpecID,PartState(1:3,PartID),&
                UNITVECTOR(PartState(4:6,PartID)),nVec,iPartBound=BCID,mode=2,MPF_optIN=MPF)
        END IF ! DoBoundaryParticleOutputHDF5
#if USE_HDG
        ! 2. Check if floating boundary conditions (FPC) are used and consider electron holes
        IF(UseFPC)THEN
          iBC = PartBound%MapToFieldBC(BCID)
          IF(iBC.LE.0) CALL abort(__STAMP__,'iBC = PartBound%MapToFieldBC(PartBCIndex) must be >0',IntInfoOpt=iBC)
          IF(BoundaryType(iBC,BC_TYPE).EQ.20)THEN ! BCType = BoundaryType(iBC,BC_TYPE)
            BCState = BoundaryType(iBC,BC_STATE) ! State is iFPC
            iUniqueFPCBC = FPC%Group(BCState,2)
            FPC%ChargeProc(iUniqueFPCBC) = FPC%ChargeProc(iUniqueFPCBC) - Species(SpecID)%ChargeIC * MPF ! Use negative charge!
          END IF ! BCType.EQ.20
        END IF ! UseFPC
        ! 3. Check if electric potential condition (EPC) are used and consider electron holes
        IF(UseEPC)THEN
          iBC = PartBound%MapToFieldBC(BCID)
          IF(iBC.LE.0) CALL abort(__STAMP__,'iBC = PartBound%MapToFieldBC(PartBCIndex) must be >0',IntInfoOpt=iBC)
          IF(BoundaryType(iBC,BC_TYPE).EQ.8)THEN ! BCType = BoundaryType(iBC,BC_TYPE)
            BCState = BoundaryType(iBC,BC_STATE) ! State is iEPC
            iUniqueEPCBC = EPC%Group(BCState,2)
            EPC%ChargeProc(iUniqueEPCBC) = EPC%ChargeProc(iUniqueEPCBC) - Species(SpecID)%ChargeIC * MPF ! Use negative charge!
          END IF ! BCType.EQ.8
        END IF ! UseEPC
#endif /*USE_HDG*/
      END DO
    END DO ! q = 1, nSurfSample
  END DO ! p = 1, nSurfSample
END DO

END ASSOCIATE

END SUBROUTINE PhotoIonization_RayTracing_SEE


SUBROUTINE PhotoIonization_RayTracing_Volume()
!===================================================================================================================================
!> Routine calculates the number of photo-ionization reactions, utilizing the cell-local photon energy from the raytracing
!===================================================================================================================================
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
! Variables
USE MOD_Globals_Vars            ,ONLY: PI, c
USE MOD_Timedisc_Vars           ,ONLY: dt,time
USE MOD_Mesh_Vars               ,ONLY: nElems, offsetElem
USE MOD_Mesh_Vars               ,ONLY: NGeo,wBaryCL_NGeo,XiCL_NGeo,XCL_NGeo
USE MOD_RayTracing_Vars         ,ONLY: UseRayTracing, Ray
USE MOD_RayTracing_Vars         ,ONLY: U_N_Ray_loc,N_DG_Ray_loc,N_Inter_Ray
USE MOD_Particle_Vars           ,ONLY: Species, PartState, usevMPF, PartMPF, PDM, PEM, PartSpecies
USE MOD_DSMC_Vars               ,ONLY: ChemReac, DSMC, SpecDSMC, BGGas, Coll_pData, CollisMode, PartStateIntEn
USE MOD_DSMC_Vars               ,ONLY: newAmbiParts, iPartIndx_NodeNewAmbi
! Functions/Subroutines
USE MOD_Eval_xyz                ,ONLY: TensorProductInterpolation
USE MOD_part_emission_tools     ,ONLY: CalcPhotonEnergy
USE MOD_DSMC_ChemReact          ,ONLY: PhotoIonization_InsertProducts
USE MOD_part_emission_tools     ,ONLY: CalcVelocity_maxwell_lpn, DSMC_SetInternalEnr_LauxVFD
USE MOD_DSMC_PolyAtomicModel    ,ONLY: DSMC_SetInternalEnr_Poly
USE MOD_part_tools              ,ONLY: CalcVelocity_maxwell_particle
!----------------------------------------------------------------------------------------------------------------------------------!
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
! INPUT VARIABLES
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: iElem,k,l,m,iReac,iPair,iGlobalElem
INTEGER               :: SpecID,nPair,NRayLoc,BGGSpecID
INTEGER               :: NbrOfRepetitions
INTEGER               :: PartID,newPartID
REAL                  :: t_1, t_2, E_Intensity, TimeScalingFactor
REAL                  :: density, NbrOfPhotons, NbrOfReactions
REAL                  :: RandNum,RandVal(3),Xi(3)
REAL                  :: RandomPos(1:3)
!===================================================================================================================================

IF(.NOT.UseRayTracing) RETURN

! TODO: Only if a photoionization reaction has been found


! Determine the time-dependent ray intensity
ASSOCIATE(tau         => Ray%PulseDuration      ,&
          tShift      => Ray%tShift             ,&
          lambda      => Ray%WaveLength         ,&
          Period      => Ray%Period)

#ifdef LSERK
IF (iStage.EQ.1) THEN
t_1 = Time
t_2 = Time + RK_c(2) * dt
ELSE
  IF (iStage.NE.nRKStages) THEN
    t_1 = Time + RK_c(iStage) * dt
    t_2 = Time + RK_c(iStage+1) * dt
  ELSE
    t_1 = Time + RK_c(iStage) * dt
    t_2 = Time + dt
  END IF
END IF
#else
t_1 = Time
t_2 = Time + dt
#endif

! Calculate the current pulse
NbrOfRepetitions = INT(Time/Period)

! Add arbitrary time shift (-4 sigma_t) so that I_max is not at t=0s
! Note that sigma_t = tau / sqrt(2)
t_1 = t_1 - tShift - NbrOfRepetitions * Period
t_2 = t_2 - tShift - NbrOfRepetitions * Period

! check if t_2 is outside of the pulse
IF(t_2.GT.2.0*tShift) t_2 = 2.0*tShift

TimeScalingFactor = 0.5 * SQRT(PI) * tau * (ERF(t_2/tau)-ERF(t_1/tau))

DO iElem=1, nElems
  iGlobalElem = iElem+offSetElem
  ! iCNElem = GetCNElemID(iGlobalElem)
  NRayLoc = N_DG_Ray_loc(iElem)
  DO m=0,NRayLoc
    DO l=0,NRayLoc
      DO k=0,NRayLoc
        ! TODO: Ray secondary energy, U_N_Ray_loc(iElem)%U(2,k,l,m)
        E_Intensity = U_N_Ray_loc(iElem)%U(1,k,l,m) * TimeScalingFactor
        ! Number of photons (TODO: spectrum)
        NbrOfPhotons = E_Intensity / (CalcPhotonEnergy(lambda) * c * dt)
        DO iReac = 1, ChemReac%NumOfReact
          SpecID = ChemReac%Reactants(iReac,1)
          ! TODO: Background gas density distribution
          BGGSpecID = BGGas%MapSpecToBGSpec(SpecID)
          density = BGGas%NumberDensity(BGGSpecID)
          ! Determine the number of particles to insert
          ! Collision number: Z = n_gas * n_ph * sigma_reac * v (in the case of photons its speed of light)
          ! Number of reactions: N = Z * dt * V (number of photons cancels out the volume)
          ! Number of reactions: N = n_gas * N_ph * sigma_reac * v * dt
          NbrOfReactions = density * NbrOfPhotons * ChemReac%CrossSection(iReac) * c * dt / Species(SpecID)%MacroParticleFactor
          CALL RANDOM_NUMBER(RandNum)
          nPair = INT(NbrOfReactions+RandNum)
          ! Loop over all newly created particles
          DO iPair = 1, nPair
            ! Get a random position in the subelement TODO: N_Inter_Ray must always be available
            CALL RANDOM_NUMBER(RandVal)
            Xi(1) = -1.0 + SUM(N_Inter_Ray(NRayLoc)%wGP(0:k-1)) + N_Inter_Ray(NRayLoc)%wGP(k) * RandVal(1)
            Xi(2) = -1.0 + SUM(N_Inter_Ray(NRayLoc)%wGP(0:l-1)) + N_Inter_Ray(NRayLoc)%wGP(l) * RandVal(2)
            Xi(3) = -1.0 + SUM(N_Inter_Ray(NRayLoc)%wGP(0:m-1)) + N_Inter_Ray(NRayLoc)%wGP(m) * RandVal(3)
            IF(ANY(Xi.GT.1.0).OR.ANY(Xi.LT.-1.0))THEN
              IPWRITE(UNIT_StdOut,*) "Xi =", Xi
              CALL abort(__STAMP__,'xi out of range')
            END IF ! ANY(Xi.GT.1.0).OR.ANY(Xi.LT.-1.0)
            ! Get the physical coordinates that correspond to the reference coordinates
            CALL TensorProductInterpolation(Xi(1:3),3,NGeo,XiCL_NGeo,wBaryCL_NGeo,XCL_NGeo(1:3,0:NGeo,0:NGeo,0:NGeo,iElem),RandomPos(1:3))
            ! Create new particle from the background gas
            PDM%CurrentNextFreePosition = PDM%CurrentNextFreePosition + 1
            PartID = PDM%nextFreePosition(PDM%CurrentNextFreePosition)
            IF(PartID.GT.PDM%ParticleVecLength) PDM%ParticleVecLength = PDM%ParticleVecLength + 1
            IF(PartID.GT.PDM%MaxParticleNumber)THEN
              CALL abort(__STAMP__,'Raytrace Photoionization: PartID.GT.PDM%MaxParticleNumber. '//&
                                  'Increase Part-maxParticleNumber or use more processors. PartID=',IntInfoOpt=PartID)
            END IF
            IF (PartID.EQ.0) THEN
              CALL Abort(__STAMP__,'ERROR in PhotoIonization: MaxParticleNumber should be increased!')
            END IF
            ! Set the position
            PartState(1:3,PartID) = RandomPos(1:3)
            ! Set the species
            PartSpecies(PartID) = SpecID
            ! Set the velocity (required for the collision energy, although relatively small compared to the photon energy)
            IF(BGGas%UseDistribution) THEN
              PartState(4:6,PartID) = CalcVelocity_maxwell_particle(SpecID,BGGas%Distribution(BGGSpecID,4:6,iElem)) &
                                            + BGGas%Distribution(BGGSpecID,1:3,iElem)
            ELSE
              CALL CalcVelocity_maxwell_lpn(FractNbr=SpecID, Vec3D=PartState(4:6,PartID), iInit=1)
            END IF
            ! Ambipolar diffusion
            IF (DSMC%DoAmbipolarDiff) THEN
              newAmbiParts = newAmbiParts + 1
              iPartIndx_NodeNewAmbi(newAmbiParts) = PartID
            END IF
            ! Set the internal energies
            IF(CollisMode.GT.1) THEN
              IF(SpecDSMC(SpecID)%PolyatomicMol) THEN
                CALL DSMC_SetInternalEnr_Poly(SpecID,1,PartID,1)
              ELSE
                CALL DSMC_SetInternalEnr_LauxVFD(SpecID,1,PartID,1)
              END IF
            END IF
            ! Particle flags
            PDM%ParticleInside(PartID)  = .TRUE.
            PDM%IsNewPart(PartID)       = .TRUE.
            PDM%dtFracPush(PartID)      = .FALSE.
            PEM%GlobalElemID(PartID)     = iGlobalElem
            PEM%LastGlobalElemID(PartID) = iGlobalElem
            ! Create second particle (only the index and the flags/elements needs to be set)
            PDM%CurrentNextFreePosition = PDM%CurrentNextFreePosition + 1
            newPartID = PDM%nextFreePosition(PDM%CurrentNextFreePosition)
            IF(newPartID.GT.PDM%ParticleVecLength) PDM%ParticleVecLength = PDM%ParticleVecLength + 1
            IF(newPartID.GT.PDM%MaxParticleNumber)THEN
              CALL abort(__STAMP__,'Raytrace Photoionization: newPartID.GT.PDM%MaxParticleNumber. '//&
                                  'Increase Part-maxParticleNumber or use more processors. newPartID=',IntInfoOpt=newPartID)
            END IF
            IF (newPartID.EQ.0) THEN
              CALL Abort(__STAMP__,'ERROR in PhotoIonization: MaxParticleNumber should be increased!')
            END IF
            IF (DSMC%DoAmbipolarDiff) THEN
              newAmbiParts = newAmbiParts + 1
              iPartIndx_NodeNewAmbi(newAmbiParts) = newPartID
            END IF
            ! Particle flags
            PDM%ParticleInside(newPartID)  = .TRUE.
            PDM%IsNewPart(newPartID)       = .TRUE.
            PDM%dtFracPush(newPartID)      = .FALSE.
            PEM%GlobalElemID(newPartID)     = iGlobalElem
            PEM%LastGlobalElemID(newPartID) = iGlobalElem
            ! Pairing (first particle is the background gas species)
            Coll_pData(iPair)%iPart_p1 = newPartID
            Coll_pData(iPair)%iPart_p2 = PartID
            ! Relative velocity is not required as the relative translational energy will not be considered
            Coll_pData(iPair)%CRela2 = 0.
            ! Weighting factor: use the weighting factor of the emission init
            IF(usevMPF) THEN
              PartMPF(PartID)    = Species(SpecID)%MacroParticleFactor
              PartMPF(newPartID) = PartMPF(PartID)
            END IF
            ! Velocity (set it to zero, as it will be subtracted in the chemistry module)
            PartState(4:6,newPartID) = 0.
            ! Internal energies (set it to zero)
            PartStateIntEn(1:2,newPartID) = 0.
            IF(DSMC%ElectronicModel.GT.0) PartStateIntEn(3,newPartID) = 0.
            ! Insert the products and distribute the reaction energy (Requires: Pair indices, Coll_pData(iPair)%iPart_p1/2)
            CALL PhotoIonization_InsertProducts(iPair, iReac, Ray%BaseVector1IC, Ray%BaseVector2IC, Ray%Direction, PartBCIndex=0)
          END DO  ! iPart = 1, nPair
        END DO    ! iReac = 1, ChemReac%NumOfReact
      END DO ! k
    END DO ! l
  END DO ! m
END DO

END ASSOCIATE

END SUBROUTINE PhotoIonization_RayTracing_Volume


! SUBROUTINE CalcPhotoIonizationNumber(iReac,iElem,NbrOfPhotons,NbrOfReactions)
! !===================================================================================================================================
! !>
! !===================================================================================================================================
! ! MODULES
! USE MOD_Globals
! USE MOD_Globals_Vars  ,ONLY: c
! USE MOD_Particle_Vars ,ONLY: Species
! USE MOD_DSMC_Vars     ,ONLY: BGGas,ChemReac
! USE MOD_TimeDisc_Vars ,ONLY: dt
! ! IMPLICIT VARIABLE HANDLING
! IMPLICIT NONE
! !-----------------------------------------------------------------------------------------------------------------------------------
! ! INPUT VARIABLES
! INTEGER, INTENT(IN)           :: i
! REAL, INTENT(IN)              :: NbrOfPhotons
! !-----------------------------------------------------------------------------------------------------------------------------------
! ! OUTPUT VARIABLES
! REAL, INTENT(OUT)             :: NbrOfReactions
! !-----------------------------------------------------------------------------------------------------------------------------------
! ! LOCAL VARIABLES
! INTEGER                       :: iReac,SpecID
! REAL                          :: density
! !===================================================================================================================================

! SpecID = ChemReac%Reactants(iReac,1)

! ! TODO: Background gas density distribution
! density = BGGas%NumberDensity(BGGas%MapSpecToBGSpec(SpecID))
! ! TODO: Variable particle weight
! ! TODO: Variable particle time step

! SELECT CASE(TRIM(ChemReac%ReactModel(iReac)))
! CASE('phIon')
!   ! Collision number: Z = n_gas * n_ph * sigma_reac * v (in the case of photons its speed of light)
!   ! Number of reactions: N = Z * dt * V (number of photons cancels out the volume)
!   NbrOfReactions = density * NbrOfPhotons * ChemReac%CrossSection(iReac) * c * dt / Species(SpecID)%MacroParticleFactor
! CASE('phIonXSec')
!   ! TODO:
! CASE DEFAULT
!   CYCLE
! END SELECT

! END SUBROUTINE CalcPhotoIonizationNumber

END MODULE MOD_Particle_Photoionization
