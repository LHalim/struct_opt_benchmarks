
subroutine computeNzPattern(n, ne, nvars, conn, vars, rowp, ncols, cols, info)
  ! Compute the non-zero pattern of the stiffness matrix given the
  ! connectivity
  !
  ! Input:
  ! n:        the number of nodes
  ! ne:       the number of elements
  ! nvars     the number of variables
  ! conn:     the element connectivity
  ! vars:     the variable numbers for each node (negative for)
  !
  ! Output:
  ! rowp:     the row pointer
  ! ncols:    the number of columns
  ! cols:     the column index
  ! info:     successful = 0, otherwise the required length of ncols

  use precision
  use quicksort
  implicit none

  ! The input data
  integer, intent(in) :: n, ne, nvars, ncols, conn(4, ne), vars(2, n)
  integer, intent(inout) :: rowp(nvars+1), cols(ncols)
  integer, intent(out) :: info

  ! Store an array of the non-zero entries
  integer :: i, j, jj, k, kk, var, count, temp
  integer :: rp, rstart, rend, index, nzeros(nvars)

  ! All entries in the row pointer
  rowp(:) = 0

  ! Compute the maximum number of entries that we'll put in each row
  do i = 1, ne
    do j = 1, 4
      ! Count up the number of entries in the matrix
      do jj = 1, 2
        ! Note that the vars array and the conn array are both
        ! zero-based indexed
        var = vars(jj, conn(j, i) + 1) + 1
        if (var > 0) then
          rowp(var) = rowp(var) + 8
        end if
      end do
    end do
  end do

  ! Count it up so that we'll have enough room
  count = 0
  do i = 1, nvars+1
    temp = rowp(i)
    rowp(i) = count
    count = count + temp
  end do

  ! Return that we have failed, and we need a larger array
  if (ncols < rowp(nvars+1)) then
     info = rowp(nvars+1)
     return
  end if

  ! We have enough room to store the whole array
  info = 0

  ! Add the non-zero pattern from each element. This includes negative
  ! indices added from the vars array
  do i = 1, ne
    do jj = 1, 2
      do j = 1, 4
        var = vars(jj, conn(j, i) + 1) + 1
        if (var > 0) then
          rp = rowp(var) + 1
          do kk = 1, 2
            do k = 1, 4
              ! Fill in the column indices with the zero-based
              ! values, not the one-based values
              cols(rp) = vars(kk, conn(k, i) + 1)
              rp = rp + 1
            end do
          end do
          rowp(var) = rp - 1
        end if
      end do
    end do
  end do

  ! Reset the pointer array
  do i = nvars, 1, -1
    rowp(i+1) = rowp(i)
  end do
  rowp(1) = 0

  ! Now, we've over-counted the entries, remove duplicates in each
  ! row. Note that this is an O(n) run time, but also has an O(n)
  ! storage requirement.
  nzeros(:) = 0

  index = 1
  rstart = 1
  do i = 1, nvars
    rend = rowp(i+1) + 1

    ! Overwrite the cols array, removing duplicates
    do rp = rstart, rend-1
      if (cols(rp) >= 0) then
        if (nzeros(cols(rp) + 1) == 0) then
          cols(index) = cols(rp)
          nzeros(cols(index) + 1) = 1
          index = index + 1
        end if
      end if
    end do

    ! Set the new end location for the row
    rowp(i+1) = index - 1

    ! Reset the array of flags
    do rp = rowp(i)+1, index-1
      nzeros(cols(rp) + 1) = 0
    end do
    rstart = rend

    call quicksortArray(cols(rowp(i)+1:rowp(i+1)))
  end do

end subroutine computeNzPattern

subroutine computeMass(n, ne, conn, X, rho, mass)
! Compute the mass of the structure given the material densities
!
! Input:
! n:        the number of nodes
! ne:       the number of elements
! conn:     the connectivity of the underlying mesh
! X:        the nodal locations in the mesh
! rho:      the density values within each element
!
! Output:
! mass:     the mass

use precision
implicit none

integer, intent(in) :: n, ne, conn(4, ne)
real(kind=dtype), intent(in) :: X(2, n)
real(kind=dtype), intent(in) :: rho(n)
real(kind=dtype), intent(out) :: mass

! Temporary data used internally
integer :: index, i, j
real(kind=dtype) :: Xd(2, 2), ns(4), nxi(4), neta(4)
real(kind=dtype) :: quadpts(2), quadwts(2)
real(kind=dtype) :: det, rval

! Zero the initial mass
mass = 0.0_dtype

! Set the Gauss quadrature point/weight values
quadpts(1) = -0.577350269189626_dtype
quadpts(2) = 0.577350269189626_dtype
quadwts(1) = 1.0_dtype
quadwts(2) = 1.0_dtype

! Loop over all elements within the mesh
do index = 1, ne
  ! Loop over the quadrature points within the finite element
  do j = 1,2
    do i = 1,2
      ! Evaluate the shape functions
      call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

      ! Evaluate the Jacobian of the residuals
      call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

      ! Compute determinant of Xd
      det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)

      ! Compute the interpolated design value
      rval = rho(conn(1, index) + 1)*ns(1) + &
             rho(conn(2, index) + 1)*ns(2) + &
             rho(conn(3, index) + 1)*ns(3) + &
             rho(conn(4, index) + 1)*ns(4)

      ! Add the contribution to the mass
      mass = mass + rval*det*quadwts(i)*quadwts(j)
    end do
  end do
end do

end subroutine computeMass

subroutine computeMassDeriv(n, ne, conn, X, dmdx)
  ! Compute the mass of the structure given the material densities
  !
  ! Input:
  ! n:        the number of nodes
  ! ne:       the number of elements
  ! conn:     the connectivity of the underlying mesh
  ! X:        the nodal locations in the mesh
  ! rho:      the density values within each element
  !
  ! Output:
  ! mass:     the mass

  use precision
  implicit none

  integer, intent(in) :: n, ne, conn(4, ne)
  real(kind=dtype), intent(in) :: X(2, n)
  real(kind=dtype), intent(inout) :: dmdx(n)

  ! Temporary data used internally
  integer :: index, i, j
  real(kind=dtype) :: Xd(2, 2), ns(4), nxi(4), neta(4)
  real(kind=dtype) :: quadpts(2), quadwts(2)
  real(kind=dtype) :: det, h, edmdx(4)

  ! Set the Gauss quadrature point/weight values
  quadpts(1) = -0.577350269189626_dtype
  quadpts(2) = 0.577350269189626_dtype
  quadwts(1) = 1.0_dtype
  quadwts(2) = 1.0_dtype

  dmdx(:) = 0.0_dtype

  ! Loop over all elements within the mesh
  do index = 1, ne
    ! Zero the element-wise derivative
    edmdx(:) = 0.0_dtype

    ! Loop over the quadrature points within the finite element
    do j = 1,2
      do i = 1,2
        ! Evaluate the shape functions
        call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

        ! Evaluate the Jacobian of the residuals
        call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

        ! Compute determinant of Xd
        det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)

        h = det*quadwts(i)*quadwts(j)

        edmdx(1) = edmdx(1) + h*ns(1)
        edmdx(2) = edmdx(2) + h*ns(2)
        edmdx(3) = edmdx(3) + h*ns(3)
        edmdx(4) = edmdx(4) + h*ns(4)
      end do
    end do

    do i = 1, 4
      dmdx(conn(i, index) + 1) = dmdx(conn(i, index) + 1) + edmdx(i)
    end do
  end do

end subroutine computeMassDeriv

subroutine computeMomOfInertia(n, ne, conn, X, rho, inertia)
  ! Compute the moment of inertia around center of mass
  ! Input:
  ! n:        the number of nodes
  ! ne:       the number of elements
  ! conn:     the connectivity of the underlying mesh
  ! X:        the nodal locations in the mesh
  ! rho:      the density values within each element
  !
  ! Output:
  ! inertia:     the moment of inertia around center of mass

  use precision
  implicit none

  integer, intent(in) :: n, ne, conn(4, ne)
  real(kind=dtype), intent(in) :: X(2, n), rho(n)
  real(kind=dtype), intent(out) :: inertia

  ! Temporary data used internally
  integer :: index, i, j
  real(kind=dtype) :: Xd(2, 2), ns(4), nxi(4), neta(4)
  real(kind=dtype) :: quadpts(2), quadwts(2)
  real(kind=dtype) :: det, rval, masse, mass
  real(kind=dtype) :: xe, ye, re2, xcg, ycg, rcg2

  ! Zero the initial moment of inertia
  inertia = 0.0_dtype
  xcg = 0.0_dtype
  ycg = 0.0_dtype

  ! Set the Gauss quadrature point/weight values
  quadpts(1) = -0.577350269189626_dtype
  quadpts(2) = 0.577350269189626_dtype
  quadwts(1) = 1.0_dtype
  quadwts(2) = 1.0_dtype

  ! Loop over all elements within the mesh
  do index = 1, ne
    ! Loop over the quadrature points within the finite element
    do j = 1,2
      do i = 1,2
        ! Evaluate the shape functions
        call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

        ! Evaluate the Jacobian of the residuals
        call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

        ! Compute determinant of Xd
        det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)

        ! Compute the interpolated design value
        rval = rho(conn(1, index) + 1)*ns(1) + &
               rho(conn(2, index) + 1)*ns(2) + &
               rho(conn(3, index) + 1)*ns(3) + &
               rho(conn(4, index) + 1)*ns(4)

        ! Compute the element mass
        masse = rval*det*quadwts(i)*quadwts(j)

        ! Compute the coordinates of current element
        xe = ( X(1, conn(1, index) + 1) + &
               X(1, conn(2, index) + 1) + &
               X(1, conn(3, index) + 1) + &
               X(1, conn(4, index) + 1) ) / 4.0
        ye = ( X(2, conn(1, index) + 1) + &
               X(2, conn(2, index) + 1) + &
               X(2, conn(3, index) + 1) + &
               X(2, conn(4, index) + 1) ) / 4.0
        re2 = xe**2 + ye**2

        ! Compute coordinates center of mass
        xcg = xcg + masse*xe
        ycg = ycg + masse*ye

        ! Add the contribution fo the total inertia
        inertia = inertia + masse*re2
      end do
    end do
  end do

  ! Compute coordinates center of mass
  call computeMass(n, ne, conn, X, rho, mass)
  xcg = xcg / mass
  ycg = ycg / mass
  rcg2 = xcg**2 + ycg**2

  ! Convert the moment inertia around origin to center of mass
  inertia = inertia - mass*rcg2

end subroutine computeMomOfInertia

subroutine computeMomOfInertiaDeriv(n, ne, conn, X, rho, dinertiadx)
  ! Compute the derivative of moment of inertia
  ! of the structure given the material densities
  !
  ! Input:
  ! n:          the number of nodes
  ! ne:         the number of elements
  ! conn:       the connectivity of the underlying mesh
  ! X:          the nodal locations in the mesh
  ! rho:      the density values within each element
  !
  ! Output:
  ! dinertiadx: the derivative of inertia

  use precision
  implicit none

  integer, intent(in) :: n, ne, conn(4, ne)
  real(kind=dtype), intent(in) :: X(2, n), rho(n)
  real(kind=dtype), intent(inout) :: dinertiadx(n)

  ! Temporary data used internally
  integer :: index, i, j
  real(kind=dtype) :: Xd(2, 2), ns(4), nxi(4), neta(4)
  real(kind=dtype) :: quadpts(2), quadwts(2)
  real(kind=dtype) :: det, h, dmdx(n), edinertiadx(4)
  real(kind=dtype) :: ed1stmomxdx(4), ed1stmomydx(4), edmdx(4)
  real(kind=dtype) :: xe, ye, re2, xcg, ycg, rcg2, mass
  real(kind=dtype) :: firstmomx, firstmomy, rval, masse

  ! Set the Gauss quadrature point/weight values
  quadpts(1) = -0.577350269189626_dtype
  quadpts(2) = 0.577350269189626_dtype
  quadwts(1) = 1.0_dtype
  quadwts(2) = 1.0_dtype

  ! Compute total mass
  call computeMass(n, ne, conn, X, rho, mass)

  ! Loop over all elements to get center of mass and 1st moments
  firstmomx = 0.0_dtype
  firstmomy = 0.0_dtype
  do index = 1, ne
    ! Loop over the quadrature points within the finite element
    do j = 1,2
      do i = 1,2
        ! Evaluate the shape functions
        call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

        ! Evaluate the Jacobian of the residuals
        call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

        ! Compute determinant of Xd
        det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)

        ! Compute the interpolated design value
        rval = rho(conn(1, index) + 1)*ns(1) + &
               rho(conn(2, index) + 1)*ns(2) + &
               rho(conn(3, index) + 1)*ns(3) + &
               rho(conn(4, index) + 1)*ns(4)

        ! Compute the element mass
        masse = rval*det*quadwts(i)*quadwts(j)

        ! Compute the coordinates of current element
        xe = ( X(1, conn(1, index) + 1) + &
               X(1, conn(2, index) + 1) + &
               X(1, conn(3, index) + 1) + &
               X(1, conn(4, index) + 1) ) / 4.0
        ye = ( X(2, conn(1, index) + 1) + &
               X(2, conn(2, index) + 1) + &
               X(2, conn(3, index) + 1) + &
               X(2, conn(4, index) + 1) ) / 4.0

        ! Compute first moments of area
        firstmomx = firstmomx + masse*xe
        firstmomy = firstmomy + masse*ye
      end do
    end do
  end do

  ! Compute center of mass
  xcg = firstmomx / mass
  ycg = firstmomy / mass
  rcg2 = xcg**2 + ycg**2

  dinertiadx(:) = 0.0_dtype

  ! Loop over all elements within the mesh
  do index = 1, ne
    ! Zero the element-wise derivative
    edinertiadx(:) = 0.0_dtype
    ed1stmomxdx(:) = 0.0_dtype
    ed1stmomydx(:) = 0.0_dtype
    edmdx(:) = 0.0_dtype

    ! Loop over the quadrature points within the finite element
    do j = 1,2
      do i = 1,2
        ! Evaluate the shape functions
        call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

        ! Evaluate the Jacobian of the residuals
        call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

        ! Compute determinant of Xd
        det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)

        ! Compute the coordinates of current element
        xe = ( X(1, conn(1, index) + 1) + &
              X(1, conn(2, index) + 1) + &
              X(1, conn(3, index) + 1) + &
              X(1, conn(4, index) + 1) ) / 4.0
        ye = ( X(2, conn(1, index) + 1) + &
              X(2, conn(2, index) + 1) + &
              X(2, conn(3, index) + 1) + &
              X(2, conn(4, index) + 1) ) / 4.0
        re2 = xe**2 + ye**2

        h = det*quadwts(i)*quadwts(j)

        edinertiadx(1) = edinertiadx(1) + h*ns(1)*re2
        edinertiadx(2) = edinertiadx(2) + h*ns(2)*re2
        edinertiadx(3) = edinertiadx(3) + h*ns(3)*re2
        edinertiadx(4) = edinertiadx(4) + h*ns(4)*re2

        ed1stmomxdx(1) = ed1stmomxdx(1) + h*ns(1)*xe
        ed1stmomxdx(2) = ed1stmomxdx(2) + h*ns(2)*xe
        ed1stmomxdx(3) = ed1stmomxdx(3) + h*ns(3)*xe
        ed1stmomxdx(4) = ed1stmomxdx(4) + h*ns(4)*xe

        ed1stmomydx(1) = ed1stmomydx(1) + h*ns(1)*ye
        ed1stmomydx(2) = ed1stmomydx(2) + h*ns(2)*ye
        ed1stmomydx(3) = ed1stmomydx(3) + h*ns(3)*ye
        ed1stmomydx(4) = ed1stmomydx(4) + h*ns(4)*ye

        edmdx(1) = edmdx(1) + h*ns(1)
        edmdx(2) = edmdx(2) + h*ns(2)
        edmdx(3) = edmdx(3) + h*ns(3)
        edmdx(4) = edmdx(4) + h*ns(4)
      end do
    end do

    do i = 1, 4
      dinertiadx(conn(i, index) + 1) = &
        dinertiadx(conn(i, index) + 1) + edinertiadx(i) &
        - 2.0*xcg*(ed1stmomxdx(i) - firstmomx/mass*edmdx(i)) &
        - 2.0*ycg*(ed1stmomydx(i) - firstmomy/mass*edmdx(i))
    end do
  end do

  ! Subtract the contribution of mass
  call computeMassDeriv(n, ne, conn, X, dmdx)
  dinertiadx = dinertiadx - rcg2*dmdx

end subroutine computeMomOfInertiaDeriv

subroutine computePenalty(rho, qval, penalty)
  ! Given the density, compute the corresponding penalty

  use precision
  implicit none

  real(kind=dtype), intent(in) :: rho, qval
  real(kind=dtype), intent(out) :: penalty
  real(kind=dtype), parameter :: one = 1.0_dtype

  penalty = rho/(one + qval*(one - rho))

end subroutine computePenalty

subroutine computePenaltyDeriv(rho, qval, penalty, dpenalty)
  ! Given the density, compute the corresponding penalty and the
  ! derivative of the penalty with respect to rho

  use precision
  implicit none

  real(kind=dtype), intent(in) :: rho, qval
  real(kind=dtype), intent(out) :: penalty, dpenalty
  real(kind=dtype), parameter :: one = 1.0_dtype

  real(kind=dtype) :: tinv
  tinv = one/(one + qval*(one - rho))
  penalty = rho*tinv
  dpenalty = (qval + one)*tinv**2

end subroutine computePenaltyDeriv

subroutine computePenalty2ndDeriv(rho, qval, penalty, dpenalty, ddpenalty)
  ! Given the density, compute the corresponding penalty and the
  ! derivative of the penalty with respect to rho

  use precision
  implicit none

  real(kind=dtype), intent(in) :: rho, qval
  real(kind=dtype), intent(out) :: penalty, dpenalty, ddpenalty
  real(kind=dtype), parameter :: one = 1.0_dtype

  real(kind=dtype) :: tinv
  tinv = one/(one + qval*(one - rho))
  penalty = rho*tinv
  dpenalty = (qval + one)*tinv**2
  ddpenalty = 2.0*qval*(qval + one)*tinv**3

end subroutine computePenalty2ndDeriv

subroutine evalShapeFunctions(xi, eta, ns, nxi, neta)
  ! Evaluate bi-linear shape functions within the element
  !
  ! Input:
  ! xi, eta:   the parametric coordinate locations on [-1, 1]^2
  !
  ! Output:
  ! ns:    the shape functions
  ! nxi:   the derivative of the shape functions w.r.t. xi
  ! neta:  the derivative of the shape functions w.r.t. eta

  use precision
  implicit none

  real(kind=dtype), intent(in) :: xi, eta
  real(kind=dtype), intent(out) :: ns(4), nxi(4), neta(4)

  ! Evaluate the shape functions for the element
  ns(1) = 0.25*(1.0 - xi)*(1.0 - eta)
  ns(2) = 0.25*(1.0 + xi)*(1.0 - eta)
  ns(3) = 0.25*(1.0 - xi)*(1.0 + eta)
  ns(4) = 0.25*(1.0 + xi)*(1.0 + eta)

  ! Evaluate the derivative of the shape functions w.r.t. xi
  nxi(1) = 0.25*(eta - 1.0)
  nxi(2) = 0.25*(1.0 - eta)
  nxi(3) = -0.25*(1.0 + eta)
  nxi(4) = 0.25*(1.0 + eta)

  ! Evaluate the derivative of the shape functions w.r.t. eta
  neta(1) = 0.25*(xi - 1.0)
  neta(2) = -0.25*(1.0 + xi)
  neta(3) = 0.25*(1.0 - xi)
  neta(4) = 0.25*(1.0 + xi)

end subroutine evalShapeFunctions

subroutine getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)
  ! Evaluate the derivative of X with respect to the local parametric
  ! coordinates.
  !
  ! Input:
  ! index:   the element index
  ! n:       the number of nodes
  ! ne:      the number of elements
  ! conn:    the element connectivity
  ! X:       the nodal locations
  ! nxi:     the derivative of the shape functions w.r.t. xi
  ! neta:    the derivative of the shape functions w.r.t. eta
  ! Xd:      the gradient w.r.t. the local coordinate system

  use precision
  implicit none

  ! The input/output declarations
  integer, intent(in) :: index, n, ne, conn(4,ne)
  real(kind=dtype), intent(in) :: X(2,n)
  real(kind=dtype), intent(in) :: nxi(4), neta(4)
  real(kind=dtype), intent(out) :: Xd(2,2)

  ! Index counter
  integer :: k

  do k = 1, 2
     Xd(k,1) = ( &
          nxi(1)*X(k, conn(1, index) + 1) + &
          nxi(2)*X(k, conn(2, index) + 1) + &
          nxi(3)*X(k, conn(3, index) + 1) + &
          nxi(4)*X(k, conn(4, index) + 1))

     Xd(k,2) = ( &
          neta(1)*X(k, conn(1, index) + 1) + &
          neta(2)*X(k, conn(2, index) + 1) + &
          neta(3)*X(k, conn(3, index) + 1) + &
          neta(4)*X(k, conn(4, index) + 1))
  end do

end subroutine getElemGradient

subroutine evalStrain(Jd, Ud, e)
  ! Given the displacement gradient ud, evaluate the strain.
  ! This uses the chain rule in the following manner:
  !
  ! U,d = U,x*X,d  ==> U,x = U,d*{X,d}^{-1} = U,d*J
  !
  ! Input:
  ! J:    the inverse of the derivative of the coords w.r.t. xi, eta
  ! Ud:   the derivative of the u,v displacements w.r.t. xi, eta
  !
  ! Output:
  ! e:    the strain

  use precision
  implicit none

  ! Input/output declarations
  real(kind=dtype), intent(in) :: Jd(2,2), Ud(2,2)
  real(kind=dtype), intent(out) :: e(3)

  ! The derivatives of the displacements
  real(kind=dtype) :: ux, uy, vx, vy

  ux = Ud(1,1)*Jd(1,1) + Ud(1,2)*Jd(2,1)
  uy = Ud(1,1)*Jd(1,2) + Ud(1,2)*Jd(2,2)

  vx = Ud(2,1)*Jd(1,1) + Ud(2,2)*Jd(2,1)
  vy = Ud(2,1)*Jd(1,2) + Ud(2,2)*Jd(2,2)

  e(1) = ux
  e(2) = vy
  e(3) = uy + vx

end subroutine evalStrain

subroutine evalBmat(Jd, nxi, neta, B)
  ! Given the matrix J = {Xd}^{-1}, and the derivatives of the shape
  ! functions, compute the derivative of the strain with respect to
  ! the displacements.
  !
  ! Input:
  ! J:    the inverse of the corrdinate derivatives matrix Xd
  ! nxi:  the derivative of the shape functions w.r.t. xi
  ! neta: the derivative of the shape functions w.r.t. eta
  !
  ! Output:
  ! B:    the derivative of the strain with respect to the displacements

  use precision
  implicit none

  ! In/out declarations
  real(kind=dtype), intent(in) :: Jd(2,2), nxi(4), neta(4)
  real(kind=dtype), intent(out) :: B(3,8)

  ! Temporary values
  integer :: i
  real(kind=dtype) :: dx, dy

  ! Zero the values
  B(:,:) = 0.0_dtype

  do i = 1,4
     dx = nxi(i)*Jd(1,1) + neta(i)*Jd(2,1)
     dy = nxi(i)*Jd(1,2) + neta(i)*Jd(2,2)

     ! Compute the derivative w.r.t. u
     B(1,2*i-1) = dx
     B(3,2*i-1) = dy

     ! Add the derivative w.r.t. v
     B(2,2*i) = dy
     B(3,2*i) = dx
  end do

end subroutine evalBmat

subroutine computeElemKmat(index, n, ne, conn, X, qval, C, rho, Ke)
  ! Evaluate the stiffness matrix for the given element number with
  ! the specified modulus of elasticity.
  !
  ! Input:
  ! index:  the element index in the connectivity array
  ! n:      the number of nodes
  ! ne:     the number of elements
  ! conn:   the connectivity
  ! X:      the x/y node locations
  ! qval:   the RAMP penalty parameter
  ! C:      the constitutive relationship
  ! rho:    the filtered design variable values at the nodes
  !
  ! Output:
  ! Ke:     the element stiffness matrix

  use precision
  implicit none

  integer, intent(in) :: index, n, ne, conn(4, ne)
  real(kind=dtype), intent(in) :: qval, X(2,n), C(3,3), rho(n)
  real(kind=dtype), intent(inout) :: Ke(8,8)

  ! Temporary data used in the element calculation
  integer :: i, j, ii, jj
  real(kind=dtype) :: B(3,8), s(3)
  real(kind=dtype) :: Xd(2,2), Jd(2,2), ns(4), nxi(4), neta(4)
  real(kind=dtype) :: quadpts(2), quadwts(2)
  real(kind=dtype) :: det, invdet, h, rval, penalty

  ! Set the Gauss quadrature point/weight values
  quadpts(1) = -0.577350269189626_dtype
  quadpts(2) = 0.577350269189626_dtype
  quadwts(1) = 1.0_dtype
  quadwts(2) = 1.0_dtype

  ! Zero all the elements in the stiffness matrix
  Ke(:,:) = 0.0_dtype

  do j = 1,2
     do i = 1,2
        ! Evaluate the shape functions
        call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

        ! Evaluate the Jacobian of the residuals
        call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

        ! Compute determinant of Xd
        det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)

        ! Compute J = Xd^{-1}
        invdet = 1.0_dtype/det
        Jd(1,1) =  invdet*Xd(2,2)
        Jd(2,1) = -invdet*Xd(2,1)
        Jd(1,2) = -invdet*Xd(1,2)
        Jd(2,2) =  invdet*Xd(1,1)

        ! Compute the interpolated design value
        rval = rho(conn(1, index) + 1)*ns(1) + &
               rho(conn(2, index) + 1)*ns(2) + &
               rho(conn(3, index) + 1)*ns(3) + &
               rho(conn(4, index) + 1)*ns(4)

        ! Compute the penalization factor for the stiffness
        call computePenalty(rval, qval, penalty)

        ! Compute the coefficient of quadrature approximation
        h = quadwts(i)*quadwts(j)*penalty*det

        ! Evaluate the derivative of the strain matrix
        call evalBmat(Jd, nxi, neta, B)

        do jj = 1,8
           s(1) = C(1,1)*B(1,jj) + C(1,2)*B(2,jj) + C(1,3)*B(3,jj)
           s(2) = C(2,1)*B(1,jj) + C(2,2)*B(2,jj) + C(2,3)*B(3,jj)
           s(3) = C(3,1)*B(1,jj) + C(3,2)*B(2,jj) + C(3,3)*B(3,jj)

           do ii = 1,8
              Ke(ii, jj) = Ke(ii, jj) + &
                   h*(s(1)*B(1,ii) + s(2)*B(2,ii) + s(3)*B(3,ii))
           end do
        end do
     end do
  end do

end subroutine computeElemKmat

subroutine computeKmat(n, ne, nvars, conn, vars, X, qval, C, rho, ncols, rowp, cols, K)
! Compute the global stiffness matrix and store it in the given
! compressed sparse row data format.
!
! Input:
! n:        the number of nodes
! ne:       the number of elements
! conn:     the element connectivity
! X:        the nodal locations
! qval:     the penalty parameter
! C:        the constitutive matrix
! rho:      the filtered design density values
! ncols:    the length of the columns array
! rowp:     the row pointer
! cols:     the column index
!
! Output:
! K:        the stiffness matrix entries

use precision
implicit none

! The input data
integer, intent(in) :: n, ne, nvars, conn(4, ne), vars(2, n)
real(kind=dtype), intent(in) :: X(2, n)
real(kind=dtype), intent(in) :: qval, C(3,3), rho(n)
integer, intent(in) :: ncols, rowp(nvars+1), cols(ncols)
real(kind=dtype), intent(inout) :: K(ncols)

! Temporary data used in the element computation
integer :: index, i, ii, j, jj, jp, ivar, jvar
real(kind=dtype) :: Ke(8,8)

! Constants used in this function
real(kind=dtype), parameter :: zero = 0.0_dtype
real(kind=dtype), parameter :: one = 1.0_dtype

! Zero all entries in the matrix
K(:) = zero

do index = 1, ne
  ! Evaluate the element stiffness matrix
  call computeElemKmat(index, n, ne, conn, X, qval, C, rho, Ke)

  ! Add the values into the stiffness matrix
  do ii = 1, 2
    do i = 1, 4
      ! ivar is the zero-based index of the variable
      ivar = vars(ii, conn(i, index) + 1)
      if (ivar >= 0) then
        do jj = 1, 2
          do j = 1, 4
            ! jvar is the zero-based index of the variable
            jvar = vars(jj, conn(j, index) + 1)
            if (jvar >= 0) then
              ! Here rowp and cols are zero-based arrays for the
              ! compressed sparse row data
              do jp = rowp(ivar+1)+1, rowp(ivar+2)
                if (cols(jp) == jvar) then
                  K(jp) = K(jp) + Ke(2*(i-1) + ii, 2*(j-1) + jj)
                end if
              end do
            end if
          end do
        end do
      end if
    end do
  end do
end do

end subroutine computeKmat

subroutine computeKmatDeriv(n, ne, nvars, conn, vars, X, qval, C, rho, psi, phi, dfdx)
  ! Compute the derivative of the inner product of two vectors with the stiffness
  ! matrix
  !
  ! Input:
  ! n:        the number of nodes
  ! ne:       the number of elements
  ! conn:     the element connectivity
  ! X:        the nodal locations
  ! qval:     the penalty parameter
  ! C:        the constitutive matrix
  ! rho:      the filtered design density values

  use precision
  implicit none

  ! The input data
  integer, intent(in) :: n, ne, nvars, conn(4, ne), vars(2, n)
  real(kind=dtype), intent(in) :: X(2, n)
  real(kind=dtype), intent(in) :: qval, C(3,3), rho(n), psi(nvars), phi(nvars)
  real(kind=dtype), intent(inout) :: dfdx(n)

  ! Temporary data used in the element calculation
  integer :: index, i, j, ii, ivar
  real(kind=dtype) :: epsi(8), ephi(8), edfdx(4)
  real(kind=dtype) :: B(3,8), bphi(3), bpsi(3), s(3)
  real(kind=dtype) :: Xd(2,2), Jd(2,2), ns(4), nxi(4), neta(4)
  real(kind=dtype) :: quadpts(2), quadwts(2)
  real(kind=dtype) :: det, invdet, h, rval, penalty, dpenalty

  ! Set the Gauss quadrature point/weight values
  quadpts(1) = -0.577350269189626_dtype
  quadpts(2) = 0.577350269189626_dtype
  quadwts(1) = 1.0_dtype
  quadwts(2) = 1.0_dtype

  dfdx(:) = 0.0_dtype

  do index = 1, ne
    ! Extract the local variables for each element
    epsi(:) = 0.0_dtype
    ephi(:) = 0.0_dtype

    do ii = 1, 2
      do i = 1, 4
        ivar = vars(ii, conn(i, index) + 1)
        if (ivar >= 0) then
          epsi(2*(i-1) + ii) = psi(ivar+1)
          ephi(2*(i-1) + ii) = phi(ivar+1)
        end if
      end do
    end do

    edfdx(:) = 0.0_dtype

    do j = 1,2
      do i = 1,2
        ! Evaluate the shape functions
        call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

        ! Evaluate the Jacobian of the residuals
        call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

        ! Compute determinant of Xd
        det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)

        ! Compute J = Xd^{-1}
        invdet = 1.0_dtype/det
        Jd(1,1) =  invdet*Xd(2,2)
        Jd(2,1) = -invdet*Xd(2,1)
        Jd(1,2) = -invdet*Xd(1,2)
        Jd(2,2) =  invdet*Xd(1,1)

        ! Compute the interpolated design value at Gauss quadrature point
        rval = rho(conn(1, index) + 1)*ns(1) + &
               rho(conn(2, index) + 1)*ns(2) + &
               rho(conn(3, index) + 1)*ns(3) + &
               rho(conn(4, index) + 1)*ns(4)

        ! Compute the penalization factor for the stiffness
        call computePenaltyDeriv(rval, qval, penalty, dpenalty)

        ! Compute the quadrature weight at this point
        h = quadwts(i)*quadwts(j)*det*dpenalty

        ! Evaluate the derivative of the strain matrix
        call evalBmat(Jd, nxi, neta, B)

        bphi = matmul(B, ephi)
        bpsi = matmul(B, epsi)

        s(1) = C(1,1)*bphi(1) + C(1,2)*bphi(2) + C(1,3)*bphi(3)
        s(2) = C(2,1)*bphi(1) + C(2,2)*bphi(2) + C(2,3)*bphi(3)
        s(3) = C(3,1)*bphi(1) + C(3,2)*bphi(2) + C(3,3)*bphi(3)

        h = h*(s(1)*bpsi(1) + s(2)*bpsi(2) + s(3)*bpsi(3))

        edfdx(1) = edfdx(1) + h*ns(1)
        edfdx(2) = edfdx(2) + h*ns(2)
        edfdx(3) = edfdx(3) + h*ns(3)
        edfdx(4) = edfdx(4) + h*ns(4)
      end do
    end do

    do i = 1, 4
      dfdx(conn(i, index)+1) = dfdx(conn(i, index)+1) + edfdx(i)
    end do
  end do

end subroutine computeKmatDeriv

subroutine computeKmat2ndDeriv(n, ne, nvars, conn, vars, X, qval, C, rho, &
    svec, psi, phi, d2fd2x)
  ! Compute the derivative of the inner product of two vectors with the stiffness
  ! matrix
  !
  ! Input:
  ! n:        the number of nodes
  ! ne:       the number of elements
  ! conn:     the element connectivity
  ! X:        the nodal locations
  ! qval:     the penalty parameter
  ! C:        the constitutive matrix
  ! rho:      the filtered design density values

  use precision
  implicit none

  ! The input data
  integer, intent(in) :: n, ne, nvars, conn(4, ne), vars(2, n)
  real(kind=dtype), intent(in) :: X(2, n)
  real(kind=dtype), intent(in) :: qval, C(3,3), rho(n), svec(n)
  real(kind=dtype), intent(in) :: psi(nvars), phi(nvars)
  real(kind=dtype), intent(inout) :: d2fd2x(n)

  ! Temporary data used in the element calculation
  integer :: index, i, j, ii, ivar
  real(kind=dtype) :: epsi(8), ephi(8), ed2fd2x(4)
  real(kind=dtype) :: B(3,8), bphi(3), bpsi(3), s(3)
  real(kind=dtype) :: Xd(2,2), Jd(2,2), ns(4), nxi(4), neta(4)
  real(kind=dtype) :: quadpts(2), quadwts(2)
  real(kind=dtype) :: det, invdet, h, rval, sval, penalty, dpenalty, ddpenalty

  ! Set the Gauss quadrature point/weight values
  quadpts(1) = -0.577350269189626_dtype
  quadpts(2) = 0.577350269189626_dtype
  quadwts(1) = 1.0_dtype
  quadwts(2) = 1.0_dtype

  d2fd2x(:) = 0.0_dtype

  do index = 1, ne
    ! Extract the local variables for each element
    epsi(:) = 0.0_dtype
    ephi(:) = 0.0_dtype

    do ii = 1, 2
      do i = 1, 4
        ivar = vars(ii, conn(i, index) + 1)
        if (ivar >= 0) then
          epsi(2*(i-1) + ii) = psi(ivar+1)
          ephi(2*(i-1) + ii) = phi(ivar+1)
        end if
      end do
    end do

    ed2fd2x(:) = 0.0_dtype

    do j = 1,2
      do i = 1,2
        ! Evaluate the shape functions
        call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

        ! Evaluate the Jacobian of the residuals
        call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

        ! Compute determinant of Xd
        det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)

        ! Compute J = Xd^{-1}
        invdet = 1.0_dtype/det
        Jd(1,1) =  invdet*Xd(2,2)
        Jd(2,1) = -invdet*Xd(2,1)
        Jd(1,2) = -invdet*Xd(1,2)
        Jd(2,2) =  invdet*Xd(1,1)

        ! Compute the interpolated design value at Gauss quadrature point
        rval = rho(conn(1, index) + 1)*ns(1) + &
               rho(conn(2, index) + 1)*ns(2) + &
               rho(conn(3, index) + 1)*ns(3) + &
               rho(conn(4, index) + 1)*ns(4)

        ! Compute the interpolated design perturbation value at Gauss quadrature point
        sval = svec(conn(1, index) + 1)*ns(1) + &
               svec(conn(2, index) + 1)*ns(2) + &
               svec(conn(3, index) + 1)*ns(3) + &
               svec(conn(4, index) + 1)*ns(4)

        ! Compute the penalization factor for the stiffness
        call computePenalty2ndDeriv(rval, qval, penalty, dpenalty, ddpenalty)

        ! Compute the quadrature weight at this point
        h = quadwts(i)*quadwts(j)*det*ddpenalty*sval

        ! Evaluate the derivative of the strain matrix
        call evalBmat(Jd, nxi, neta, B)

        bphi = matmul(B, ephi)
        bpsi = matmul(B, epsi)

        s(1) = C(1,1)*bphi(1) + C(1,2)*bphi(2) + C(1,3)*bphi(3)
        s(2) = C(2,1)*bphi(1) + C(2,2)*bphi(2) + C(2,3)*bphi(3)
        s(3) = C(3,1)*bphi(1) + C(3,2)*bphi(2) + C(3,3)*bphi(3)

        h = h*(s(1)*bpsi(1) + s(2)*bpsi(2) + s(3)*bpsi(3))

        ed2fd2x(1) = ed2fd2x(1) + h*ns(1)
        ed2fd2x(2) = ed2fd2x(2) + h*ns(2)
        ed2fd2x(3) = ed2fd2x(3) + h*ns(3)
        ed2fd2x(4) = ed2fd2x(4) + h*ns(4)
      end do
    end do

    do i = 1, 4
      d2fd2x(conn(i, index)+1) = d2fd2x(conn(i, index)+1) + ed2fd2x(i)
    end do
  end do

end subroutine computeKmat2ndDeriv

subroutine computeElemMmat(index, n, ne, conn, X, density, rho, Me)
  ! Evaluate the mass matrix for the given element number with
  ! the specified modulus of elasticity.
  !
  ! Input:
  ! index:   the element index in the connectivity array
  ! n:       the number of nodes
  ! ne:      the number of elements
  ! conn:    the connectivity
  ! X:       the x/y node locations
  ! density: the density of the material
  ! rho:     the filtered design variable values at the nodes
  !
  ! Output:
  ! Me:      the element mass matrix

  use precision
  implicit none

  integer, intent(in) :: index, n, ne, conn(4, ne)
  real(kind=dtype), intent(in) :: X(2,n), density, rho(n)
  real(kind=dtype), intent(inout) :: Me(8,8)

  ! Temporary data used in the element calculation
  integer :: i, j, ii, jj
  real(kind=dtype) :: Xd(2,2), Jd(2,2), ns(4), nxi(4), neta(4)
  real(kind=dtype) :: quadpts(2), quadwts(2)
  real(kind=dtype) :: det, invdet, h, rval

  ! Set the Gauss quadrature point/weight values
  quadpts(1) = -0.577350269189626_dtype
  quadpts(2) = 0.577350269189626_dtype
  quadwts(1) = 1.0_dtype
  quadwts(2) = 1.0_dtype

  ! Zero all the elements in the stiffness matrix
  Me(:,:) = 0.0_dtype

  do j = 1,2
    do i = 1,2
      ! Evaluate the shape functions
      call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

      ! Evaluate the Jacobian of the residuals
      call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

      ! Compute J = Xd^{-1}
      det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)
      invdet = 1.0_dtype/det
      Jd(1,1) =  invdet*Xd(2,2)
      Jd(2,1) = -invdet*Xd(2,1)
      Jd(1,2) = -invdet*Xd(1,2)
      Jd(2,2) =  invdet*Xd(1,1)

      ! Compute the interpolated design value
      rval = rho(conn(1, index) + 1)*ns(1) + &
             rho(conn(2, index) + 1)*ns(2) + &
             rho(conn(3, index) + 1)*ns(3) + &
             rho(conn(4, index) + 1)*ns(4)

      ! Compute the quadrature weight at this point
      h = quadwts(i)*quadwts(j)*rval*det*density

      do jj = 1,4
        do ii = 1,4
          Me(2*(ii-1) + 1, 2*(jj-1) + 1) = Me(2*(ii-1) + 1, 2*(jj-1) + 1) + h*ns(ii)*ns(jj)
          Me(2*(ii-1) + 2, 2*(jj-1) + 2) = Me(2*(ii-1) + 2, 2*(jj-1) + 2) + h*ns(ii)*ns(jj)
        end do
      end do
    end do
  end do

end subroutine computeElemMmat

subroutine computeMmat(n, ne, nvars, conn, vars, X, &
  density, rho, ncols, rowp, cols, M)
! Compute the global mass matrix and store it in the given
! compressed sparse row data format.
!
! Input:
! n:        the number of nodes
! ne:       the number of elements
! nvars:    the number of variables
! conn:     the element connectivity
! vars:     the variable numbers
! X:        the nodal locations
! density:  the material density value
! rho:      the filtered design density values
! ncols:    the length of the columns array
! rowp:     the row pointer
! cols:     the column index
!
! Output:
! M:        the mass matrix entries

use precision
implicit none

! The input data
integer, intent(in) :: n, ne, nvars, conn(4, ne), vars(2, n)
real(kind=dtype), intent(in) :: X(2, n)
real(kind=dtype), intent(in) :: density, rho(n)
integer, intent(in) :: ncols, rowp(nvars+1), cols(ncols)
real(kind=dtype), intent(inout) :: M(ncols)

! Temporary data used in the element computation
integer :: index, i, ii, j, jj, jp, ivar, jvar
real(kind=dtype) :: Me(8,8)

! Constants used in this function
real(kind=dtype), parameter :: zero = 0.0_dtype
real(kind=dtype), parameter :: one = 1.0_dtype

! Zero all entries in the matrix
M(:) = zero

do index = 1, ne
  ! Evaluate the element stiffness matrix
  call computeElemMmat(index, n, ne, conn, X, density, rho, Me)

  ! Add the values into the stiffness matrix
  do ii = 1, 2
    do i = 1, 4
      ! ivar is the zero-based index of the variable
      ivar = vars(ii, conn(i, index) + 1)
      if (ivar >= 0) then
        do jj = 1, 2
          do j = 1, 4
            ! jvar is the zero-based index of the variable
            jvar = vars(jj, conn(j, index) + 1)
            if (jvar >= 0) then
              ! Here rowp and cols are zero-based arrays for the
              ! compressed sparse row data
              do jp = rowp(ivar+1)+1, rowp(ivar+2)
                if (cols(jp) == jvar) then
                  M(jp) = M(jp) + Me(2*(i-1) + ii, 2*(j-1) + jj)
                end if
              end do
            end if
          end do
        end do
      end if
    end do
  end do
end do

end subroutine computeMmat

subroutine computeMmatDeriv(n, ne, nvars, conn, vars, X, density, psi, phi, dfdx)
  ! Compute the derivative of the inner product of two vectors with the mass
  ! matrix
  !

  use precision
  implicit none

  ! The input data
  integer, intent(in) :: n, ne, nvars, conn(4, ne), vars(2, n)
  real(kind=dtype), intent(in) :: X(2, n)
  real(kind=dtype), intent(in) :: density, psi(nvars), phi(nvars)
  real(kind=dtype), intent(inout) :: dfdx(n)

  ! Temporary data used in the element calculation
  integer :: index, i, j, ii, ivar
  real(kind=dtype) :: epsi(8), ephi(8), edfdx(4)
  real(kind=dtype) :: u1, v1, u2, v2
  real(kind=dtype) :: Xd(2,2), Jd(2,2), ns(4), nxi(4), neta(4)
  real(kind=dtype) :: quadpts(2), quadwts(2)
  real(kind=dtype) :: det, invdet, h

  ! Set the Gauss quadrature point/weight values
  quadpts(1) = -0.577350269189626_dtype
  quadpts(2) = 0.577350269189626_dtype
  quadwts(1) = 1.0_dtype
  quadwts(2) = 1.0_dtype

  dfdx(:) = 0.0_dtype

  do index = 1, ne
    ! Extract the local variables for each element
    epsi(:) = 0.0_dtype
    ephi(:) = 0.0_dtype

    do ii = 1, 2
      do i = 1, 4
        ivar = vars(ii, conn(i, index) + 1)
        if (ivar >= 0) then
          epsi(2*(i-1) + ii) = psi(ivar+1)
          ephi(2*(i-1) + ii) = phi(ivar+1)
        end if
      end do
    end do

    edfdx(:) = 0.0_dtype

    do j = 1,2
      do i = 1,2
        ! Evaluate the shape functions
        call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

        ! Evaluate the Jacobian of the residuals
        call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

        ! Compute J = Xd^{-1}
        det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)
        invdet = 1.0_dtype/det
        Jd(1,1) =  invdet*Xd(2,2)
        Jd(2,1) = -invdet*Xd(2,1)
        Jd(1,2) = -invdet*Xd(1,2)
        Jd(2,2) =  invdet*Xd(1,1)

        ! Compute the quadrature weight at this point
        h = quadwts(i)*quadwts(j)*det*density

        u1 = ns(1)*epsi(1) + ns(2)*epsi(3) + ns(3)*epsi(5) + ns(4)*epsi(7)
        v1 = ns(1)*epsi(2) + ns(2)*epsi(4) + ns(3)*epsi(6) + ns(4)*epsi(8)

        u2 = ns(1)*ephi(1) + ns(2)*ephi(3) + ns(3)*ephi(5) + ns(4)*ephi(7)
        v2 = ns(1)*ephi(2) + ns(2)*ephi(4) + ns(3)*ephi(6) + ns(4)*ephi(8)

        h = h*(u1*u2 + v1*v2)

        edfdx(1) = edfdx(1) + h*ns(1)
        edfdx(2) = edfdx(2) + h*ns(2)
        edfdx(3) = edfdx(3) + h*ns(3)
        edfdx(4) = edfdx(4) + h*ns(4)
      end do
    end do

    do i = 1, 4
      dfdx(conn(i, index)+1) = dfdx(conn(i, index)+1) + edfdx(i)
    end do
  end do

end subroutine computeMmatDeriv

subroutine computeQuadPos(n, ne, conn, X, xpos, ypos)
! Compute coordinates of quadrature points

  use precision
  implicit none

  integer, intent(in) :: n, ne, conn(4, ne)
  real(kind=dtype), intent(in) :: X(2, n)
  real(kind=dtype), intent(inout) :: xpos(4, ne), ypos(4, ne)

  ! Temporary data used internally
  integer :: index, i, j
  real(kind=dtype) :: quadpts(2), ns(4), nxi(4), neta(4)

  ! Set the Gauss quadrature point/weight values
  quadpts(1) = -0.577350269189626_dtype
  quadpts(2) = 0.577350269189626_dtype

  do index = 1, ne
    do j = 1,2
      do i = 1,2
        ! Evaluate the shape functions
        call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

        ! Compute the interpolated x coordinate
        xpos(2*(j-1) + i, index) = &
          X(1, conn(1, index) + 1)*ns(1) + &
          X(1, conn(2, index) + 1)*ns(2) + &
          X(1, conn(3, index) + 1)*ns(3) + &
          X(1, conn(4, index) + 1)*ns(4)

        ! Compute the interpolated y coordinate
        ypos(2*(j-1) + i, index) = &
          X(2, conn(1, index) + 1)*ns(1) + &
          X(2, conn(2, index) + 1)*ns(2) + &
          X(2, conn(3, index) + 1)*ns(3) + &
          X(2, conn(4, index) + 1)*ns(4)

      end do
    end do
  end do

end subroutine

subroutine computeStress( &
  n, ne, nvars, conn, vars, X, &
  epsilon, C, u, rho, stress)
! Compute the stress value at each quadrature point in each element
! in the mesh
!

use precision
implicit none

integer, intent(in) :: n, ne, nvars, conn(4, ne), vars(2, n)
real(kind=dtype), intent(in) :: X(2,n), u(nvars), rho(n)
real(kind=dtype), intent(in) :: epsilon, C(3,3)
real(kind=dtype), intent(inout) :: stress(4, ne)

! Temporary data used internally
integer ::  index, i, j, ivar
real(kind=dtype) :: e(3), s(3), B(3, 8), ue(8)
real(kind=dtype) :: Xd(2,2), Jd(2,2), ns(4), nxi(4), neta(4)
real(kind=dtype) :: quadpts(2)
real(kind=dtype) :: det, invdet, rval, factor

! Set the parameter
real(kind=dtype), parameter :: one = 1.0_dtype

! Set the Gauss quadrature point/weight values
quadpts(1) = -0.577350269189626_dtype
quadpts(2) = 0.577350269189626_dtype

do index = 1, ne
  ! Extract the displacements at the nodes
  ue(:) = 0.0_dtype
  do i = 1, 2
    do j = 1, 4
      ivar = vars(i, conn(j, index) + 1)
      if (ivar >= 0) then
        ue(2*(j-1) + i) = u(ivar+1)
      end if
    end do
  end do

  do j = 1,2
    do i = 1,2
      ! Evaluate the shape functions
      call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

      ! Evaluate the Jacobian of the residuals
      call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

      ! Compute determinant of Xd
      det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)

      ! Compute J = Xd^{-1}
      invdet = 1.0_dtype/det
      Jd(1,1) =  invdet*Xd(2,2)
      Jd(2,1) = -invdet*Xd(2,1)
      Jd(1,2) = -invdet*Xd(1,2)
      Jd(2,2) =  invdet*Xd(1,1)

      ! Compute the interpolated design value
      rval = rho(conn(1, index) + 1)*ns(1) + &
             rho(conn(2, index) + 1)*ns(2) + &
             rho(conn(3, index) + 1)*ns(3) + &
             rho(conn(4, index) + 1)*ns(4)

             ! Evaluate the derivative of the strain matrix
      call evalBmat(Jd, nxi, neta, B)

      e = matmul(B, ue)
      s = matmul(C, e)

      ! Compute the stress relaxation factor
      factor = rval/(epsilon*(1.0_dtype - rval) + rval)

      ! Compute the von Mises stress
      stress(2*(j-1) + i, index) = &
        factor*sqrt(s(1)**2 + s(2)**2 - s(1)*s(2) + 3*s(3)**2)
    end do
  end do
end do

end subroutine computeStress

subroutine computeStressDeriv( &
  n, ne, nvars, conn, vars, X, &
  epsilon, C, u, rho, dfdstress, dfdrho)
! Compute the stress value at each quadrature point in each element
! in the mesh
!

use precision
implicit none

integer, intent(in) :: n, ne, nvars, conn(4, ne), vars(2, n)
real(kind=dtype), intent(in) :: X(2,n), u(nvars), rho(n)
real(kind=dtype), intent(in) :: epsilon, C(3,3)
real(kind=dtype), intent(in) :: dfdstress(4, ne)
real(kind=dtype), intent(inout) :: dfdrho(n)

! Temporary data used internally
integer ::  index, i, j, k, ivar
real(kind=dtype) :: e(3), s(3), B(3, 8), ue(8)
real(kind=dtype) :: Xd(2,2), Jd(2,2), ns(4), nxi(4), neta(4)
real(kind=dtype) :: quadpts(2)
real(kind=dtype) :: det, invdet, rval, dfactor, stress

! Set the parameter
real(kind=dtype), parameter :: one = 1.0_dtype

! Set the Gauss quadrature point/weight values
quadpts(1) = -0.577350269189626_dtype
quadpts(2) = 0.577350269189626_dtype

dfdrho(:) = 0.0_dtype

do index = 1, ne
  ! Extract the displacements at the nodes
  ue(:) = 0.0_dtype
  do i = 1, 2
    do j = 1, 4
      ivar = vars(i, conn(j, index) + 1)
      if (ivar >= 0) then
        ue(2*(j-1) + i) = u(ivar+1)
      end if
    end do
  end do

  do j = 1,2
    do i = 1,2
      ! Evaluate the shape functions
      call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

      ! Evaluate the Jacobian of the residuals
      call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

      ! Compute determinant of Xd
      det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)

      ! Compute J = Xd^{-1}
      invdet = 1.0_dtype/det
      Jd(1,1) =  invdet*Xd(2,2)
      Jd(2,1) = -invdet*Xd(2,1)
      Jd(1,2) = -invdet*Xd(1,2)
      Jd(2,2) =  invdet*Xd(1,1)

      ! Compute the interpolated design value
      rval = rho(conn(1, index) + 1)*ns(1) + &
             rho(conn(2, index) + 1)*ns(2) + &
             rho(conn(3, index) + 1)*ns(3) + &
             rho(conn(4, index) + 1)*ns(4)

             ! Evaluate the derivative of the strain matrix
      call evalBmat(Jd, nxi, neta, B)

      e = matmul(B, ue)
      s = matmul(C, e)

      ! Compute the stress relaxation factor
      dfactor = epsilon/(epsilon*(1.0_dtype - rval) + rval)**2

      ! Add the factor from the derivative of the function with respect to
      ! the stress
      dfactor = dfactor*dfdstress(2*(j-1) + i, index)

      ! Compute the von Mises stress
      stress = sqrt(s(1)**2 + s(2)**2 - s(1)*s(2) + 3*s(3)**2)

      ! Compute the von Mises stress
      do k = 1, 4
        dfdrho(conn(k, index)+1) = dfdrho(conn(k, index)+1) + ns(k)*dfactor*stress
      end do
    end do
  end do
end do

end subroutine computeStressDeriv

subroutine computeStressStateDeriv( &
  n, ne, nvars, conn, vars, X, &
  epsilon, C, u, rho, dfdstress, dfdu)
! Compute the stress value at each quadrature point in each element
! in the mesh
!

use precision
implicit none

integer, intent(in) :: n, ne, nvars, conn(4, ne), vars(2, n)
real(kind=dtype), intent(in) :: X(2,n), u(nvars), rho(n)
real(kind=dtype), intent(in) :: epsilon, C(3,3), dfdstress(4, ne)
real(kind=dtype), intent(inout) :: dfdu(nvars)

! Temporary data used internally
integer ::  index, i, j, ivar
real(kind=dtype) :: e(3), s(3), B(3, 8), ue(8)
real(kind=dtype) :: Xd(2,2), Jd(2,2), ns(4), nxi(4), neta(4)
real(kind=dtype) :: quadpts(2), dfdue(8), dfds(3), dfde(3)
real(kind=dtype) :: det, invdet, rval, factor, stress

! Set the parameter
real(kind=dtype), parameter :: one = 1.0_dtype

! Set the Gauss quadrature point/weight values
quadpts(1) = -0.577350269189626_dtype
quadpts(2) = 0.577350269189626_dtype

dfdu(:) = 0.0_dtype

do index = 1, ne
  ! Extract the displacements at the nodes
  ue(:) = 0.0_dtype
  do i = 1, 2
    do j = 1, 4
      ivar = vars(i, conn(j, index) + 1)
      if (ivar >= 0) then
        ue(2*(j-1) + i) = u(ivar+1)
      end if
    end do
  end do

  dfdue(:) = 0.0_dtype

  do j = 1,2
    do i = 1,2
      ! Evaluate the shape functions
      call evalShapeFunctions(quadpts(i), quadpts(j), ns, nxi, neta)

      ! Evaluate the Jacobian of the residuals
      call getElemGradient(index, n, ne, conn, X, nxi, neta, Xd)

      ! Compute determinant of Xd
      det = Xd(1,1)*Xd(2,2) - Xd(1,2)*Xd(2,1)

      ! Compute J = Xd^{-1}
      invdet = 1.0_dtype/det
      Jd(1,1) =  invdet*Xd(2,2)
      Jd(2,1) = -invdet*Xd(2,1)
      Jd(1,2) = -invdet*Xd(1,2)
      Jd(2,2) =  invdet*Xd(1,1)

      ! Compute the interpolated design value
      rval = rho(conn(1, index) + 1)*ns(1) + &
             rho(conn(2, index) + 1)*ns(2) + &
             rho(conn(3, index) + 1)*ns(3) + &
             rho(conn(4, index) + 1)*ns(4)

             ! Evaluate the derivative of the strain matrix
      call evalBmat(Jd, nxi, neta, B)

      e = matmul(B, ue)
      s = matmul(C, e)

      ! Compute the stress relaxation factor
      factor = rval/(epsilon*(1.0_dtype - rval) + rval)

      ! Add the factor from the derivative of the function with
      ! respect to the stress at this quadrautre point
      factor = factor*dfdstress(2*(j-1) + i, index)

      ! Compute the von Mises stress
      stress = sqrt(s(1)**2 + s(2)**2 - s(1)*s(2) + 3*s(3)**2)

      ! Compute the derivative of the stress
      dfds(1) = factor*(s(1) - 0.5_dtype*s(2))/stress
      dfds(2) = factor*(s(2) - 0.5_dtype*s(1))/stress
      dfds(3) = factor*(3.0_dtype*s(3))/stress

      dfde = matmul(C, dfds)

      dfdue = dfdue + matmul(transpose(B), dfde)
    end do
  end do

  do i = 1, 2
    do j = 1, 4
      ivar = vars(i, conn(j, index) + 1)
      if (ivar >= 0) then
        dfdu(ivar+1) = dfdu(ivar+1) + dfdue(2*(j-1) + i)
      end if
    end do
  end do
end do

end subroutine computeStressStateDeriv

subroutine computeNodalStress(surelemssize, n, ne, nvars, &
  surelems, nsurelems, conn, vars, X, epsilon, C, u, rho, nodalstress)
  ! Compute the nodal stress using superconvergent patch theorey

  use precision
  implicit none
  external :: dsysv

  integer, intent(in) :: surelemssize, n, ne, nvars
  integer, intent(in) :: surelems(surelemssize), nsurelems(n)
  integer, intent(in) :: conn(4, ne), vars(2, n)
  real(kind=dtype), intent(in) :: X(2, n), epsilon, C(3, 3)
  real(kind=dtype), intent(in) :: u(nvars), rho(n)
  real(kind=dtype), intent(inout) :: nodalstress(n)

  ! Internally used variables
  integer :: index, i, j, elemptr, info
  real(kind=dtype) :: xpos(4, ne), ypos(4, ne)
  real(kind=dtype) :: A(4, 4), b(4), pnode(4), pi(4, 1)
  real(kind=dtype) :: xi, yi, xnode, ynode
  real(kind=dtype) :: quad_stress(4, ne), piv(4), work(4)

  ! Zero out nodal stress
  nodalstress(:) = 0.0_dtype

  ! Get coordinates for quadrature points
  xpos(:,:) = 0.0_dtype
  ypos(:,:) = 0.0_dtype
  call computeQuadPos(n, ne, conn, X, xpos, ypos)

  ! Compute stress at quadrature points
  quad_stress(:,:) = 0.0_dtype
  call computeStress(n, ne, nvars, conn, vars, X, &
                     epsilon, C, u, rho, quad_stress)

  ! Loop over nodes and solve for least square problems
  elemptr = 1
  do index = 1, n

    ! zero out A and b
    A(:,:) = 0.0_dtype
    b(:) = 0.0_dtype

    ! Loop over all quadrature points in adjacent elements of
    ! current node to construct A and b
    do i = 1, nsurelems(index)
      do j = 1, 4
        xi = xpos(j, surelems(elemptr)+1)
        yi = ypos(j, surelems(elemptr)+1)
        pi(1,1) = 1.0_dtype
        pi(2,1) = xi
        pi(3,1) = yi
        pi(4,1) = xi*yi
        A = A + matmul(pi, transpose(pi))
        b(:) = b + quad_stress(j, surelems(elemptr)+1)*pi(:, 1)
      end do
      elemptr = elemptr + 1
    end do

    ! Solve linear system Ax=b using LAPACK
    call dsysv('U', 4, 1, A, 4, piv, b, 4, work, 4, info)

    ! Get nodal stress
    xnode = X(1, index)
    ynode = X(2, index)
    pnode(1) = 1.0_dtype
    pnode(2) = xnode
    pnode(3) = ynode
    pnode(4) = xnode*ynode
    nodalstress(index) = dot_product(b, pnode)
  end do

end subroutine computeNodalStress

subroutine computeNodalStressDeriv(surelemssize, n ,ne, surelems, &
  nsurelems, conn, X, dfdns, dfdstress)
! Compute derivative of function of interest w.r.t. quadrature stress
! dfdstress given the derivative of function w.r.t. nodal stress dfdns.
! By chain rule, we have:
!   dfdstress (1 by 4*ne) = dfdns (1 by n) * dnsds (n by 4*ne)

  use precision
  implicit none
  external :: dsysv

  integer, intent(in) :: surelemssize, n, ne, conn(4, ne)
  integer, intent(in) :: surelems(surelemssize), nsurelems(n)
  real(kind=dtype), intent(in) :: X(2, n), dfdns(n)
  real(kind=dtype), intent(inout) :: dfdstress(4*ne)

  ! Implicitly used variables
  integer :: index, i, j, elemptr, info
  real(kind=dtype) :: xpos(4, ne), ypos(4, ne)
  real(kind=dtype) :: xi, yi, xnode, ynode
  real(kind=dtype) :: A(4, 4), B(4, 4), pi(4, 1), pnode(4)
  real(kind=dtype) :: piv(4), work(4)

  ! Zero out dfds
  dfdstress(:) = 0.0_dtype

  ! Get coordinates for quadrature points
  xpos(:,:) = 0.0_dtype
  ypos(:,:) = 0.0_dtype
  call computeQuadPos(n, ne, conn, X, xpos, ypos)

  ! Loop over nodesindex
  elemptr = 1
  do index = 1, n

    ! Zero out A
    A(:,:) = 0.0_dtype

    ! Loop over all quadrature points to get A
    do i = 1, nsurelems(index)
      do j = 1, 4
        xi = xpos(j, surelems(elemptr)+1)
        yi = ypos(j, surelems(elemptr)+1)
        pi(1,1) = 1.0_dtype
        pi(2,1) = xi
        pi(3,1) = yi
        pi(4,1) = xi*yi
        A = A + matmul(pi, transpose(pi))
      end do
      elemptr = elemptr + 1
    end do

    ! Revert pointer
    elemptr = elemptr - nsurelems(index)

    ! Compute nodal polynomial
    xnode = X(1, index)
    ynode = X(2, index)
    pnode(1) = 1.0_dtype
    pnode(2) = xnode
    pnode(3) = ynode
    pnode(4) = xnode*ynode

    ! Populate dfdstress
    do i = 1, nsurelems(index)
      do j = 1, 4
        xi = xpos(j, surelems(elemptr)+1)
        yi = ypos(j, surelems(elemptr)+1)
        pi(1,1) = 1.0_dtype
        pi(2,1) = xi
        pi(3,1) = yi
        pi(4,1) = xi*yi

        ! Make a copy of A
        B(:,:) = A(:,:)

        ! Apply inv(A) to pi
        call dsysv('U', 4, 1, B, 4, piv, pi, 4, work, 4, info)

        ! Update dfdstress entry
        dfdstress(4*surelems(elemptr)+j) = &
          dfdstress(4*surelems(elemptr)+j) + &
          dfdns(index)*dot_product(pnode, pi(:,1))
        end do
      elemptr = elemptr + 1
    end do
  end do

end subroutine computeNodalStressDeriv