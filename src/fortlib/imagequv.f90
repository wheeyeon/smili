module image
  !$use omp_lib
  use param, only : dp, dpc, pi, e, i_dpc, deps
  implicit none
  ! Epsiron for Zero judgement
  !real(dp), parameter :: zeroeps = epsilon(1d0)
  real(dp), parameter :: zeroeps = 1d-10
contains
!-------------------------------------------------------------------------------
! Calc cost function
!-------------------------------------------------------------------------------
subroutine calc_cost_reg(&
    I1d, xidx, yidx, Nxref, Nyref, Nx, Ny, &
    l1_l, l1_wgt, l1_Nwgt,&
    tv_l, tv_wgt, tv_Nwgt,&
    tsv_l, tsv_wgt, tsv_Nwgt,&
    pkl_l, pkl_wgt, pkl_Nwgt,&
    gs_l, gs_wgt, gs_Nwgt,&
    tfd_l, tfd_tgtfd,&
    cen_l, cen_alpha,&
    sm_l, sm_maj, sm_min, sm_phi,&
    l1_cost, tv_cost, tsv_cost, pkl_cost, gs_cost,&
    tfd_cost, cen_cost, sm_cost,&
    out_maj, out_min, out_phi,&
    cost, gradcost, &
    N1d)
  implicit none

  ! Image
  integer,  intent(in)  :: N1d, Nx, Ny
  integer,  intent(in)  :: xidx(N1d), yidx(N1d)
  real(dp), intent(in)  :: I1d(N1d)
  real(dp), intent(in)  :: Nxref, Nyref

  ! parameter for l1
  real(dp), intent(in)  :: pl1_l              ! lambda
  integer,  intent(in)  :: pl1_Nwgt           ! size of the weight vector
  real(dp), intent(in)  :: pl1_wgt(pl1_Nwgt)   ! weight

  ! parameter for total variation
  real(dp), intent(in)  :: ptv_l              ! lambda
  integer,  intent(in)  :: ptv_Nwgt           ! size of the weight vector
  real(dp), intent(in)  :: ptv_wgt(ptv_Nwgt)   ! weight

  ! parameter for total squared variation
  real(dp), intent(in)  :: ptsv_l             ! lambda
  integer,  intent(in)  :: ptsv_Nwgt          ! size of the weight vector
  real(dp), intent(in)  :: ptsv_wgt(ptsv_Nwgt) ! weight

  ! parameter for pkl divergence
  real(dp), intent(in)  :: pkl_l              ! lambda
  integer,  intent(in)  :: pkl_Nwgt           ! size of the weight vector
  real(dp), intent(in)  :: pkl_wgt(pkl_Nwgt)   ! weight

  ! parameter for Gull & Skilling entropy
  real(dp), intent(in)  :: pgs_l              ! lambda
  integer,  intent(in)  :: pgs_Nwgt           ! size of the weight vector
  real(dp), intent(in)  :: pgs_wgt(pgs_Nwgt)   ! weight

  ! parameter for the total flux density regularization
  real(dp), intent(in)  :: tfd_l             ! lambda (Normalized)
  real(dp), intent(in)  :: tfd_tgtfd         ! target total flux

  ! parameter for the centoroid regularization
  real(dp), intent(in)  :: cen_l             ! lambda (Normalized)
  real(dp), intent(in)  :: cen_alpha         ! alpha

  ! parameter for second momentum
  real(dp), intent(in)   :: sm_l              ! lambda
  real(dp), intent(in)   :: sm_maj,sm_min,sm_phi ! major, minor size and position angle

  ! regularization function
  real(dp), intent(out) :: l1_cost    ! cost of l1
  real(dp), intent(out) :: tv_cost    ! cost of tv
  real(dp), intent(out) :: tsv_cost   ! cost of tsv
  real(dp), intent(out) :: pkl_cost    ! cost of pkl divergence
  real(dp), intent(out) :: gs_cost    ! cost of GS entropy
  real(dp), intent(out) :: tfd_cost   ! cost of total flux regularization
  real(dp), intent(out) :: cen_cost   ! cost of centoroid regularizaiton
  real(dp), intent(out) :: sm_cost    ! cost of second moment

  ! second moment variables
  real(dp), intent(out) :: out_maj, out_min, out_phi

  ! Total Cost function
  real(dp), intent(out) :: cost             ! cost function
  real(dp), intent(out) :: gradcost(1:N1d)  ! gradient of the cost function

  ! integer and real
  integer   :: ipix
  real(dp)  :: tmp

  ! allocatable arrays
  real(dp), allocatable :: I2d(:,:)
  real(dp), allocatable :: tmp1d(:)
  real(dp)  :: Isum, xcen, ycen, Sg(3), mom(2)

  ! Initialize
  l1_cost     = 0d0
  tv_cost     = 0d0
  tsv_cost    = 0d0
  gs_cost     = 0d0
  pkl_cost     = 0d0
  tfd_cost    = 0d0
  cen_cost    = 0d0
  sm_cost     = 0d0
  cost        = 0d0
  gradcost(:) = 0d0

  ! Totalflux regularization
  if (tfd_l > 0) then
    call calc_tfdreg(I1d,tfd_tgtfd,tfd_cost,tmp,N1d)
    tfd_cost = tfd_l * tfd_cost
    gradcost = gradcost + tfd_l * tmp
  end if

  ! Center of mass regularization
  if (cen_l > 0) then
    allocate(tmp1d(N1d))
    call calc_cenreg(I1d,xidx,yidx,Nxref,Nyref,cen_alpha,tmp,tmp1d,N1d)
    cen_cost = cen_l * tmp
    gradcost = gradcost + cen_l * tmp1d
    deallocate(tmp1d)
  end if
  ! Compute pixel-based regularizations (MEM, l1, tv, tsv)
  !   Allocate two dimensional array if needed
  if (tv_l > 0 .or. tsv_l > 0) then
    allocate(I2d(Nx,Ny))
    I2d(:,:)=0d0
    call I1d_I2d_fwd(xidx,yidx,I1d,I2d,N1d,Nx,Ny)
  end if
  !
  !$OMP PARALLEL DO DEFAULT(SHARED) &
  !$OMP   FIRSTPRIVATE(N1d, I1d, I2d, xidx, yidx,&
  !$OMP                l1_l,  l1_wgt,&
  !$OMP                tv_l,  tv_wgt,&
  !$OMP                tsv_l, tsv_wgt,&
  !$OMP                gs_l,  gs_wgt,&
  !$OMP                pkl_l,  pkl_wgt,&
  !$OMP                sm_l,  sm_maj, sm_min, sm_phi) &
  !$OMP   PRIVATE(ipix) &
  !$OMP   REDUCTION(+: l1_cost, tv_cost, tsv_cost, gs_cost, pkl_cost, gradcost)

  ! second momentum regularizer
  Isum = totalflux(I1d,N1d)
  call xy_cen(I1d, xidx, yidx, N1d, xcen, ycen)
  call Sigma(I1d, xidx, yidx, N1d, Isum, xcen, ycen, Sg)
  call one_momentum(I1d, xidx, yidx, N1d, mom)
  if (sm_l>0) then
    sm_cost = sm_cost + sm_l * sm_e(Sg, sm_maj, sm_min, sm_phi)
  end if

  ! check variables of second momentum
  call check_sm_character(Sg, out_maj, out_min, out_phi)

  do ipix=1, N1d
    ! weighted L1
    if (l1_l > 0) then
      l1_cost = l1_cost + l1_l * l1_wgt(ipix) * l1_e(I1d(ipix))
      gradcost(ipix) = gradcost(ipix) + l1_l * l1_wgt(ipix) * l1_grade(I1d(ipix))
    end if

    ! pkl divergence
    if (pkl_l > 0) then
      pkl_cost = pkl_cost + pkl_l * pkl_e(I1d(ipix),pkl_wgt(ipix))
      gradcost(ipix) = gradcost(ipix) + pkl_l * pkl_grade(I1d(ipix),pkl_wgt(ipix))
    end if

    ! GS Entropy
    if (gs_l > 0) then
      gs_cost = gs_cost + gs_l * gs_e(I1d(ipix),gs_wgt(ipix))
      gradcost(ipix) = gradcost(ipix) + gs_l * gs_grade(I1d(ipix),gs_wgt(ipix))
    end if

    ! TV
    if (tv_l > 0) then
      tv_cost = tv_cost + tv_l * tv_wgt(ipix) * tv_e(xidx(ipix),yidx(ipix),I2d,Nx,Ny)
      gradcost(ipix) = gradcost(ipix) + tv_l * tv_wgt(ipix) * tv_grade(xidx(ipix),yidx(ipix),I2d,Nx,Ny)
    end if

    ! TSV
    if (tsv_l > 0) then
      tsv_cost = tsv_cost + tsv_l * tsv_wgt(ipix) * tsv_e(xidx(ipix),yidx(ipix),I2d,Nx,Ny)
      gradcost(ipix) = gradcost(ipix) + tsv_l * tsv_wgt(ipix) * tsv_grade(xidx(ipix),yidx(ipix),I2d,Nx,Ny)
    end if

    ! Gradient of second momentum regularizer
    if (sm_l>0) then
      gradcost(ipix) = gradcost(ipix) + sm_l * sm_grade(I1d(ipix), xidx(ipix), &
                        yidx(ipix), Isum, xcen, ycen, Sg, mom, sm_maj, sm_min, sm_phi)
    end if

  end do
  !$OMP END PARALLEL DO

  ! de allocate array if needed
  if (tv_l > 0 .or. tsv_l > 0) then
    deallocate(I2d)
  end if

  ! take summation of all the cost function
  cost = l1_cost + tv_cost + tsv_cost + pkl_cost + gs_cost + tfd_cost + cen_cost +sm_cost
end subroutine

!-------------------------------------------------------------------------------
! Isotropic Total Variation
!   Approximate that it can be differentiable everywhere
!-------------------------------------------------------------------------------
! Initialize the total variation
subroutine init_tvreg(xidx,yidx,Nx,Ny,tv_isflat,tv_prior,tv_wgt,N1d)

  integer,  intent(in)  :: N1d,Nx,Ny ! Number of Pixels
  integer,  intent(in)  :: xidx(N1d), yidx(N1d)
  logical,  intent(in)  :: tv_isflat
  real(dp), intent(in)  :: tv_prior(N1d)
  real(dp), intent(out) :: tv_wgt(N1d)

  if (tv_isflat .eqv. .True.) then
    ! Flat prior
    tv_wgt(:) = 1/(zeroeps + sum(tv_prior))/N1d
  else
    ! (re-)weighted TV
    call calc_tv_wgt(tv_prior,xidx,yidx,Nx,Ny,tv_wgt,N1d)
  end if
end subroutine


! derive the weights
subroutine calc_tv_wgt(I1d,xidx,yidx,Nx,Ny,tv_wgt,N1d)
  implicit none

  integer,  intent(in) :: N1d,Nx,Ny ! Number of Pixels
  real(dp), intent(in) :: I1d(N1d)  ! Input Image
  integer,  intent(in) :: xidx(N1d), yidx(N1d)
  real(dp), intent(out):: tv_wgt(N1d) ! weight

  integer   :: ipix
  real(dp)  :: I2d(Nx,Ny)

  ! copy the array to the 2d image
  I2d = 0d0
  call I1d_I2d_fwd(xidx,yidx,I1d,I2d,N1d,Nx,Ny)

  ! compute weights
  do ipix=1, N1d
    tv_wgt(ipix) = 1/tv_e(xidx(ipix),yidx(ipix),I2d,Nx,Ny)
  end do

  ! Normalize weights
  tv_wgt = tv_wgt/tv(I1d,xidx,yidx,Nx,Ny,tv_wgt,N1d)
end subroutine


! compute the Total Variation
real(dp) function tv(I1d,xidx,yidx,Nx,Ny,tv_wgt,N1d)
  implicit none

  integer,  intent(in) :: N1d,Nx,Ny ! Number of Pixels
  real(dp), intent(in) :: I1d(N1d)  ! Input Image
  integer, intent(in) :: xidx(1:N1d), yidx(1:N1d)
  real(dp), intent(in) :: tv_wgt(N1d) ! weight

  integer   :: ipix
  real(dp)  :: I2d(Nx,Ny)

  ! copy the array to the 2d image
  I2d = 0d0
  call I1d_I2d_fwd(xidx,yidx,I1d,I2d,N1d,Nx,Ny)

  ! compute weights
  tv = 0d0
  do ipix=1, N1d
    tv = tv + tv_e(xidx(ipix),yidx(ipix),I2d,Nx,Ny) * tv_wgt(ipix)
  end do
end function
!
!
real(dp) function tv_e(xidx,yidx,I2d,Nx,Ny)
  implicit none
  !
  integer,  intent(in)  ::Nx,Ny,xidx,yidx
  real(dp), intent(in)  ::I2d(Nx,Ny)
  !
  integer   ::i1,j1,i2,j2
  real(dp)  ::dIx,dIy
  !
  i1 = xidx
  j1 = yidx
  i2 = i1 + 1
  j2 = j1 + 1

  ! dIx = I(i+1,j) - I(i,j)
  if (i2 > Nx) then
    dIx = 0d0
  else
    dIx = I2d(i2,j1) - I2d(i1,j1)
  end if

  ! dIy = I(i,j+1) - I(i,j)
  if (j2 > Ny) then
    dIy = 0d0
  else
    dIy = I2d(i1,j2) - I2d(i1,j1)
  end if
  !
  ! smooth TV
  tv_e = sqrt(dIx*dIx+dIy*dIy+zeroeps)
end function
!
!
! Gradient of Isotropic Total Variation
real(dp) function tv_grade(xidx,yidx,I2d,Nx,Ny)
  implicit none
  !
  integer, intent(in) :: Nx,Ny
  integer, intent(in) :: xidx, yidx
  real(dp),intent(in) :: I2d(Nx,Ny)
  !
  ! variables
  integer :: i0,j0,i1,j1,i2,j2
  real(dp):: dIx,dIy,tv_e
  !
  ! initialize tsv term
  tv_grade = 0d0
  !
  ! take indice
  i1 = xidx
  j1 = yidx
  i0 = i1 - 1
  j0 = j1 - 1
  i2 = i1 + 1
  j2 = j1 + 1
  !
  !-------------------------------------
  ! (i2,j1)-(i1,j1), (i1,j2)-(i1,j1)
  !-------------------------------------
  ! dIx = I(i+1,j) - I(i,j)
  if (i2 > Nx) then
    dIx = 0d0
  else
    dIx = I2d(i2,j1) - I2d(i1,j1)
  end if
  !
  ! dIy = I(i,j+1) - I(i,j)
  if (j2 > Ny) then
    dIy = 0d0
  else
    dIy = I2d(i1,j2) - I2d(i1,j1)
  end if
  !
  !tv_e = sqrt(dIx*dIx+dIy*dIy)
  !if (tv_e > zeroeps) then
  !  tv_grade = tv_grade - (dIx + dIy)/tv_e
  !end if
  !
  ! Smooth TV
  tv_e = sqrt(dIx*dIx+dIy*dIy+zeroeps)
  tv_grade = tv_grade - (dIx + dIy)/tv_e
  !
  !-------------------------------------
  ! (i1,j1)-(i0,j1), (i0,j2)-(i0,j1)
  !-------------------------------------
  if (i0 > 0) then
    ! dIx = I(i,j) - I(i-1,j)
    dIx = I2d(i1,j1) - I2d(i0,j1)

    ! dIy = I(i-1,j+1) - I(i,j)
    if (j2 > Ny) then
      dIy = 0d0
    else
      dIy = I2d(i0,j2) - I2d(i0,j1)
    end if

    !tv_e = sqrt(dIx*dIx+dIy*dIy)
    !if (tv_e > zeroeps) then
    !  tv_grade = tv_grade + dIx/tv_e
    !end if
    !
    ! Smooth TV
    tv_e = sqrt(dIx*dIx+dIy*dIy+zeroeps)
    tv_grade = tv_grade + dIx/tv_e
  end if
  !
  !-------------------------------------
  ! (i2,j0)-(i1,j0), (i1,j1)-(i1,j0)
  !-------------------------------------
  if (j0 > 0) then
    ! dIy = I(i,j) - I(i,j-1)
    dIy = I2d(i1,j1) - I2d(i1,j0)

    ! dIx = I(i+1,j-1) - I(i,j-1)
    if (i2 > Nx) then
      dIx = 0d0
    else
      dIx = I2d(i2,j0) - I2d(i1,j0)
    end if

    !tv_e = sqrt(dIx*dIx+dIy*dIy)
    !if (tv_e > zeroeps) then
    !  tv_grade = tv_grade + dIy/tv_e
    !end if
    !
    ! Smooth TV
    tv_e = sqrt(dIx*dIx+dIy*dIy+zeroeps)
    tv_grade = tv_grade + dIx/tv_e
  end if
  !
end function
!
!
!-------------------------------------------------------------------------------
! Total Squared Variation
!   Approximate that it can be differentiable everywhere
!-------------------------------------------------------------------------------
! Initialize the total squared variation
subroutine init_tsvreg(xidx,yidx,Nx,Ny,tsv_isflat,tsv_prior,tsv_wgt,N1d)
  integer,  intent(in)  :: N1d, Nx, Ny
  integer,  intent(in)  :: xidx(1:N1d), yidx(1:N1d)  ! pixel coordinate
  logical,  intent(in)  :: tsv_isflat
  real(dp), intent(in)  :: tsv_prior(N1d)
  real(dp), intent(out) :: tsv_wgt(N1d)

  if (tsv_isflat .eqv. .True.) then
    ! flat prior
    tsv_wgt(:) = 1/(zeroeps + sum(tsv_prior)**2/N1d)/N1d
  else
    ! (re)weighted TSV
    call calc_tsv_wgt(tsv_prior,xidx,yidx,Nx,Ny,tsv_wgt,N1d)
  end if
end subroutine


! derive the weights
subroutine calc_tsv_wgt(I1d,xidx,yidx,Nx,Ny,tsv_wgt,N1d)
  implicit none

  integer,  intent(in) :: N1d,Nx, Ny    ! Number of Pixels,
  integer,  intent(in) :: xidx(1:N1d), yidx(1:N1d)  ! pixel coordinate
  real(dp), intent(in) :: I1d(N1d)      ! Input Image
  real(dp), intent(out):: tsv_wgt(N1d)  ! weight

  ! compute weights
  tsv_wgt = 1/(I1d**2+zeroeps)

  ! Normalize weights
  tsv_wgt = tsv_wgt/tsv(I1d,xidx,yidx,Nx,Ny,tsv_wgt,N1d)
end subroutine


! compute the Total Variation
real(dp) function tsv(I1d,xidx,yidx,Nx,Ny,tsv_wgt,N1d)
  implicit none

  integer,  intent(in) :: N1d,Nx,Ny                 ! Number of Pixels
  real(dp), intent(in) :: I1d(N1d)                  ! Input Image
  integer,  intent(in) :: xidx(1:N1d), yidx(1:N1d)  ! pixel coordinate
  real(dp), intent(in) :: tsv_wgt(N1d)              ! weight

  integer   :: ipix
  real(dp)  :: I2d(Nx,Ny)

  ! copy the array to the 2d image
  I2d = 0d0
  call I1d_I2d_fwd(xidx,yidx,I1d,I2d,N1d,Nx,Ny)

  ! compute weights
  tsv = 0d0
  do ipix=1, N1d
    tsv = tsv + tsv_e(xidx(ipix),yidx(ipix),I2d,Nx,Ny) * tsv_wgt(ipix)
  end do
end function


real(dp) function tsv_e(xidx,yidx,I2d,Nx,Ny)
  implicit none
  !
  integer, intent(in)  :: Nx,Ny,xidx,yidx
  real(dp),intent(in)  :: I2d(Nx,Ny)
  !
  ! variables
  integer :: i1,j1,i2,j2
  real(dp):: dIx,dIy
  !
  ! initialize tsv term
  i1 = xidx
  j1 = yidx
  i2 = i1 + 1
  j2 = j1 + 1
  !
  ! dIx = I(i+1,j) - I(i,j)
  if (i2 > Nx) then
    dIx = 0d0
  else
    dIx  = I2d(i2,j1) - I2d(i1,j1)
  end if
  !
  ! dIy = I(i,j+1) - I(i,j)
  if (j2 > Ny) then
    dIy = 0d0
  else
    dIy  = I2d(i1,j2) - I2d(i1,j1)
  end if
  !
  tsv_e = dIx*dIx+dIy*dIy
end function


! Gradient of Total Squared Variation
real(dp) function tsv_grade(xidx,yidx,I2d,Nx,Ny)
  implicit none
  !
  integer, intent(in)  :: Nx,Ny
  integer, intent(in)  :: xidx, yidx
  real(dp),intent(in)  :: I2d(Nx,Ny)
  !
  ! variables
  integer :: i0,j0,i1,j1,i2,j2
  !
  ! initialize tsv term
  tsv_grade = 0d0
  !
  ! take indice
  i1 = xidx
  j1 = yidx
  i0 = i1 - 1
  j0 = j1 - 1
  i2 = i1 + 1
  j2 = j1 + 1
  !
  ! dIx = I(i+1,j) - I(i,j)
  if (i2 <= Nx) then
    tsv_grade = tsv_grade - 2*(I2d(i2,j1) - I2d(i1,j1))
  end if
  !
  ! dIy = I(i,j+1) - I(i,j)
  if (j2 <= Ny) then
    tsv_grade = tsv_grade - 2*(I2d(i1,j2) - I2d(i1,j1))
  end if
  !
  ! dIx = I(i,j) - I(i-1,j)
  if (i0 > 0) then
    tsv_grade = tsv_grade + 2*(I2d(i1,j1) - I2d(i0,j1))
  end if
  !
  ! dIy = I(i,j) - I(i,j-1)
  if (j0 > 0) then
    tsv_grade = tsv_grade + 2*(I2d(i1,j1) - I2d(i1,j0))
  end if
  !
end function

!-------------------------------------------------------------------------------
! IQUV <---> m, phi, theta
!-------------------------------------------------------------------------------
subroutine mphitheta_QUV_fwd(I,m,phi,theta,Q,U,V,N1d)
  implicit none
  integer,  intent(in) :: N1d
  real(dp), intent(in) :: I(N1d)
  real(dp), intent(in) :: m(N1d),phi(N1d),theta(N1d)
  real(dp), intent(out):: Q(N1d),U(N1d),V(N1d)

  P = I*m
  cosphi = cos(phi)
  sinphi = sin(phi)
  !costhe = cos(theta)
  !sinthe = sin(theta)

  Q = P*cosphi*costhe
  U = P*sinphi*costhe
  !V = P*sinthe
end subroutine

subroutine mphitheta_QUV_inv(I,m,phi,theta,Q,U,V,N1d)
  implicit none
  integer,  intent(in) :: N1d
  real(dp), intent(in) :: I(N1d)
  real(dp), intent(out):: m(N1d),phi(N1d),theta(N1d)
  real(dp), intent(in) :: Q(N1d),U(N1d),V(N1d)
  m = sqrt(Q**2+U**2+V**2)/I
  P = sqrt(Q**2+U**2)
  phi   = atan2(U,Q)
  theta = atan2(V,P)
end subroutine

subroutine mphitheta_QUV_grad_inv(&
    I,m,phi,theta,&
    Qg,Ug,Vg,&
    mg,phig,thetag,&
    N1d)
  implicit none
  integer,  intent(in) :: N1d
  real(dp), intent(in) :: I(N1d)
  real(dp), intent(in) :: m(N1d),phi(N1d),theta(N1d)
  real(dp), intent(out):: mg(N1d),phig(N1d),thetag(N1d)

  P = I*m
  cosphi = cos(phi)
  sinphi = sin(phi)
  costhe = cos(theta)
  sinthe = sin(theta)

  mg     =  I*cosphi*costhe*Qg + I*sinphi*costhe*Ug + I*sinthe*Vg
  phig   = -P*sinphi*costhe*Qg + P*cosphi*costhe*Ug
  thetag = -P*cosphi*sinthe*Qg - P*sinphi*sinthe*Ug + P*costhe*Vg
end subroutine

!-------------------------------------------------------------------------------
end module
