Program main
    use sort

    implicit none 
    
    integer :: allocerr,samples,q,outliers
    real(kind=8) :: alpha,epsilon,delta,sigmin,fxk,fxtrial,ti,sigma
    real(kind=8), allocatable :: xtrial(:),faux(:),indices(:),nu_l(:),nu_u(:),opt_cond(:),&
                                 xstar(:),xk(:),grad(:,:),y(:),data(:,:),t(:)
    integer, allocatable :: Idelta(:)

    ! LOCAL SCALARS
    logical :: checkder
    integer :: hnnzmax,inform,jcnnzmax,m,n,nvparam
    real(kind=8) :: cnorm,efacc,efstain,eoacc,eostain,epsfeas,epsopt,f,nlpsupn,snorm

    ! LOCAL ARRAYS
    character(len=80) :: specfnm,outputfnm,vparam(10)
    logical :: coded(11)
    real(kind=8),   pointer :: l(:),u(:),x(:)

    integer :: i
    real(kind=8), dimension(3,3) :: solutions

    ! Reading data and storing it in the variables t and y
    Open(Unit = 100, File = "output/seropositives.txt", ACCESS = "SEQUENTIAL")

    ! Set parameters
    read(100,*) samples

    n = 4
    alpha = 0.5d0
    epsilon = 1.0d-4
    q = samples - 4

    allocate(t(samples),y(samples),x(n),xk(n-1),xtrial(n-1),l(n),u(n),xstar(n-1),data(4,samples),&
    faux(samples),indices(samples),Idelta(samples),nu_l(n-1),nu_u(n-1),opt_cond(n-1),stat=allocerr)

    if ( allocerr .ne. 0 ) then
        write(*,*) 'Allocation error in main program'
        stop
    end if

    do i = 1, samples
        read(100,*) data(:,i)
    enddo

    close(100)

    ! Number of days
    t(:) = data(1,:)

    ! Coded subroutines
    coded(1:6)  = .true.  ! evalf, evalg, evalh, evalc, evaljac, evalhc
    coded(7:11) = .false. ! evalfc,evalgjac,evalgjacp,evalhl,evalhlp

    ! Upper bounds on the number of sparse-matrices non-null elements
    jcnnzmax = 10000
    hnnzmax  = 10000

    ! Checking derivatives?
    checkder = .false.

    ! Parameters setting
    epsfeas   = 1.0d-08
    epsopt    = 1.0d-08
  
    efstain   = sqrt( epsfeas )
    eostain   = epsopt ** 1.5d0
  
    efacc     = sqrt( epsfeas )
    eoacc     = sqrt( epsopt )

    outputfnm = ''
    specfnm   = ''

    nvparam   = 1
    vparam(1) = 'ITERATIONS-OUTPUT-DETAIL 0' 

    l(1:n-1) = 0.0d0; l(n) = -1.0d+20
    u(1:n-1) = 1.0d+20; u(n) = 0.0d0

    ! Open(Unit = 100, File = "output/table_severalq.txt", ACCESS = "SEQUENTIAL")

    ! do q = 30, 40
    !     call ovo_algorithm(q,delta_grid(optind_delta),sigmin_grid(optind_sigmin),fobj,norm_grad)
    !     print*, q, xk, fobj, norm_grad
    !     write(100,10) q,'&',xk(1),'&',xk(2),'&',xk(3),'&',xk(4),'&',fobj,'&',n_iter,'\\'
    !     10 format (I2,1X,A1,1X,F10.6,1X,A1,1X,F10.6,1X,A1,1X,F10.6,1X,A1,1X,F10.6,1X,A1,1X,F10.6,1X,A1,1X,I3,1X,A2)
    ! end do

    ! close(100)

    ! Open(Unit = 100, File = "output/ls_measles.txt", ACCESS = "SEQUENTIAL")
    ! read(100,*) xk(1)
    ! read(100,*) xk(2)
    ! read(100,*) xk(3)
    ! close(100)

    solutions(:,:) = 0.0d0

    ! Measles
    y(:) = data(2,:)
    xk(:) = (/0.197d0,0.287d0,0.021d0/)
    xk(:) = 1.0d0
    delta = 1.0d-2
    sigmin = 1.0d-2
    call ovo_algorithm(q,delta,sigmin)
    print*,"Solution measles: ",xk
    solutions(1,:) = xk(:)

    ! ! Mumps
    ! t(:) = data(3,:)
    ! y(:) = data(4,:)
    ! xk(:) = (/0.156d0,0.250d0,0.0d0/)
    ! xk(:) = 1.0d0
    ! delta = 1.0d-2
    ! sigmin = 1.0d-2
    ! call ovo_algorithm(q,delta,sigmin)
    ! print*,"Solution mumps: ",xk
    ! solutions(2,:) = xk(:)

    ! ! Rubella
    ! t(:) = data(5,:)
    ! y(:) = data(6,:)
    ! xk(:) = (/0.0628d0,0.178d0,0.020d0/)
    ! xk(:) = 1.0d0
    ! delta = 1.0d-2
    ! sigmin = 1.0d-2
    ! call ovo_algorithm(q,delta,sigmin)
    ! print*,"Solution rubella: ",xk
    ! solutions(3,:) = xk(:)

    call export(solutions)

    CONTAINS

    !==============================================================================
    ! MAIN ALGORITHM
    !==============================================================================
    subroutine ovo_algorithm(q,delta,sigmin)
        implicit none

        integer,        intent(in) :: q
        real(kind=8),   intent(in) :: delta, sigmin

        logical,        pointer :: equatn(:),linear(:)
        real(kind=8),   pointer :: lambda(:)

        integer, parameter  :: max_iter = 100000, max_iter_sub = 1000, kflag = 2
        integer             :: iter,iter_sub,i,j
        real(kind=8)        :: gaux1,gaux2,a,b,c,ebt,terminate

        iter = 0
    
        indices(:) = (/(i, i = 1, samples)/)
    
        ! Scenarios
        do i = 1, samples
            call fi(xk,i,n,faux(i))
        end do
    
        ! Sorting
        call DSORT(faux,indices,samples,kflag)
    
        ! q-Order-Value function 
        fxk = faux(q)
    
        call mount_Idelta(faux,indices,delta,Idelta,m)

        do
            iter = iter + 1
    
            allocate(equatn(m),linear(m),lambda(m),grad(m,n-1),stat=allocerr)
    
            if ( allocerr .ne. 0 ) then
                write(*,*) 'Allocation error in main program'
                stop
            end if
    
            equatn(:) = .false.
            linear(:) = .false.
            lambda(:) = 0.0d0
    
            a = xk(1)
            b = xk(2)
            c = xk(3)
    
            do i = 1, m
                ti = t(Idelta(i))

                ebt = exp(-b * ti)

                call model(xk,Idelta(i),n,gaux1)

                gaux1 = y(Idelta(i)) - gaux1

                gaux2 = exp((a / b) * ti * ebt + (1.0d0 / b) * ((a / b) - c) * (ebt - 1.0d0) - c * ti)
    
                grad(i,1) = (1.0d0 / b**2) * (ebt - 1.0d0) + (1.0d0 / b) * (ti * ebt)
    
                grad(i,2) = (1.0d0 / b**2) * (c - a/b) * (ebt - 1.0d0)
                grad(i,2) = grad(i,2) - (1.0d0 / b**3) * (a * (ebt - 1.0d0))
                grad(i,2) = grad(i,2) + (1.0d0 / b) * ti * ebt * (c - a/b)
                grad(i,2) = grad(i,2) - (1.0d0 / b**2) * (a * ti * ebt)
                grad(i,2) = grad(i,2) - (1.0d0 / b) * (a * (ti**2) * ebt)
    
                grad(i,3) = (1.0d0 / b) * (1.0d0 - ebt) - ti
    
                grad(i,:) = gaux1 * gaux2 * grad(i,:)
            end do
    
            sigma = sigmin
    
            iter_sub = 1
            x(:) = (/xk(:),0.0d0/)
            ! x = 0.0d0
    
            ! Minimizing using ALGENCAN
            do 
                call algencan(myevalf,myevalg,myevalh,myevalc,myevaljac,myevalhc,   &
                    myevalfc,myevalgjac,myevalgjacp,myevalhl,myevalhlp,jcnnzmax,    &
                    hnnzmax,epsfeas,epsopt,efstain,eostain,efacc,eoacc,outputfnm,   &
                    specfnm,nvparam,vparam,n,x,l,u,m,lambda,equatn,linear,coded,    &
                    checkder,f,cnorm,snorm,nlpsupn,inform)

                xtrial(1:n-1) = x(1:n-1)
    
                indices(:) = (/(i, i = 1, samples)/)
    
                ! Scenarios
                do i = 1, samples
                    call fi(xtrial,i,n,faux(i))
                end do
    
                ! Sorting
                call DSORT(faux,indices,samples,kflag)
        
                fxtrial = faux(q)
        
                ! Test the sufficient descent condition
                if (fxtrial .le. (fxk - alpha * norm2(xtrial(1:n-1) - xk(1:n-1))**2)) exit
                if (iter_sub .ge. max_iter_sub) exit
    
                sigma = 2.0d0 * sigma
                iter_sub = iter_sub + 1
            end do ! End of internal iterations
    
            opt_cond(:) = 0.0d0
            nu_l(:) = 0.0d0
            nu_u(:) = 0.0d0
    
            do j = 1, n-1
                if (xtrial(j) .le. l(j)) then 
                    do i = 1, m
                        nu_l(j) = nu_l(j) + lambda(i) * grad(i,j)
                    end do
                else if (xtrial(j) .ge. u(j)) then
                    do i = 1, m
                        nu_u(j) = nu_u(j) - lambda(i) * grad(i,j)
                    end do
                end if
            end do
    
            do i = 1, m
                opt_cond(:) = opt_cond(:) + lambda(i) * grad(i,:)
            enddo
    
            opt_cond(:) = opt_cond(:) + nu_u(:) - nu_l(:)

            ! terminate = norm2(xk - xtrial)
            terminate = norm2(opt_cond)
    
            ! print*, iter, iter_sub, fxtrial, terminate, m

            deallocate(lambda,equatn,linear,grad)

            fxk = fxtrial

            xk(1:n-1) = xtrial(1:n-1)
            
            if (terminate .le. epsilon) exit
            if (iter .ge. max_iter) exit
    
            call mount_Idelta(faux,indices,delta,Idelta,m)

    
        end do ! End of Main Algorithm
        
    end subroutine

    !==============================================================================
    ! 
    !==============================================================================
    subroutine quadatic_error(x,n,res)
        implicit none 

        integer,        intent(in) :: n
        real(kind=8),   intent(in) :: x(n-1)
        real(kind=8),   intent(out) :: res
        integer :: i
        real(kind=8) :: aux

        res = 0.0d0

        do i = 1, samples
            call model(x,i,n,aux)
            aux = aux - y(i)
            res = res + aux**2
        enddo

    end subroutine quadatic_error

    !==============================================================================
    ! EXPORT RESULT TO PLOT
    !==============================================================================
    subroutine export(xsol)
        implicit none

        real(kind=8),   intent(in) :: xsol(n-1,n-1)

        Open(Unit = 100, File = "output/solutions_ovo.txt", ACCESS = "SEQUENTIAL")

        write(100,110) xsol(1,1), xsol(1,2), xsol(1,3)
        write(100,110) xsol(2,1), xsol(2,2), xsol(2,3)
        write(100,110) xsol(3,1), xsol(3,2), xsol(3,3)

        110 format (F8.6,1X,F8.6,1X,F8.6)
    
        close(100)

    end subroutine export

    !==============================================================================
    ! MOUNT THE SET OF INDICES I(x,delta)
    !==============================================================================
    subroutine mount_Idelta(f,indices,delta,Idelta,m)
        implicit none

        real(kind=8),   intent(in) :: delta,f(samples),indices(samples)
        integer,        intent(out) :: Idelta(samples),m
        integer :: i
        real(kind=8) :: fq

        Idelta(:) = 0
        fq = f(q)
        m = 0

        do i = 1, samples
            if (abs(fq - f(i)) .le. delta) then
                m = m + 1
                Idelta(m) = int(indices(i))
            end if
        end do

    end subroutine

    !==============================================================================
    ! QUADRATIC ERROR OF EACH SCENARIO
    !==============================================================================
    subroutine fi(x,i,n,res)
        implicit none

        integer,        intent(in) :: n,i
        real(kind=8),   intent(in) :: x(n-1)
        real(kind=8),   intent(out) :: res
        
        call model(x,i,n,res)
        res = res - y(i)
        res = 0.5d0 * (res**2)

    end subroutine fi

    !==============================================================================
    ! MODEL TO BE FITTED TO THE DATA
    !==============================================================================
    subroutine model(x,i,n,res)
        implicit none 

        integer,        intent(in) :: n,i
        real(kind=8),   intent(in) :: x(n-1)
        real(kind=8),   intent(out) :: res
        real(kind=8) :: a,b,c,ti,ebt

        a = x(1)
        b = x(2)
        c = x(3)
        ti = t(i)
        ebt = exp(-b * ti)

        res = (a / b) * ti * ebt
        res = res + (1.0d0 / b) * ((a / b) - c) * (ebt - 1.0d0) 
        res = 1.0d0 - exp(res - c * ti)

    end subroutine model

    !==============================================================================
    ! SUBROUTINES FOR ALGENCAN
    !==============================================================================

    !******************************************************************************
    ! OBJECTIVE FUNCTION
    !******************************************************************************
    subroutine myevalf(n,x,f,flag)
        implicit none

        ! SCALAR ARGUMENTS
        integer, intent(in) :: n
        integer, intent(out) :: flag
        real(kind=8), intent(out) :: f

        ! ARRAY ARGUMENTS
        real(kind=8), intent(in) :: x(n)

        ! Compute objective function

        flag = 0

        f = x(n)

    end subroutine myevalf

    !******************************************************************************
    ! GRADIENT OF THE OBJECTIVE FUNCTION
    !******************************************************************************
    subroutine myevalg(n,x,g,flag)
        implicit none

        ! SCALAR ARGUMENTS
        integer, intent(in) :: n
        integer, intent(out) :: flag

        ! ARRAY ARGUMENTS
        real(kind=8), intent(in) :: x(n)
        real(kind=8), intent(out) :: g(n)

        ! Compute gradient of the objective function

        flag = 0

        g(1:n-1) = 0.0d0
        g(n)     = 1.0d0

    end subroutine myevalg

    !******************************************************************************
    ! HESSIAN FOR THE OBJECTIVE FUNCTION
    !******************************************************************************
    subroutine myevalh(n,x,hrow,hcol,hval,hnnz,lim,lmem,flag)
        implicit none

        ! SCALAR ARGUMENTS
        logical, intent(out) :: lmem
        integer, intent(in) :: lim,n
        integer, intent(out) :: flag,hnnz

        ! ARRAY ARGUMENTS
        integer, intent(out) :: hcol(lim),hrow(lim)
        real(kind=8), intent(in)  :: x(n)
        real(kind=8), intent(out) :: hval(lim)

        ! Compute (lower triangle of the) Hessian of the objective function
        flag = 0
        lmem = .false.
        hnnz = 0
    end subroutine myevalh

    !******************************************************************************
    ! CONSTRAINTS
    !******************************************************************************
    subroutine myevalc(n,x,ind,c,flag)
        implicit none

        ! SCALAR ARGUMENTS
        integer, intent(in) :: ind,n
        integer, intent(out) :: flag
        real(kind=8), intent(out) :: c

        ! ARRAY ARGUMENTS
        real(kind=8), intent(in) :: x(n)

        ! Compute ind-th constraint
        flag = 0

        c = dot_product(x(1:n-1) - xk(1:n-1),grad(ind,1:n-1)) + &
            (sigma * 0.5d0) * (norm2(x(1:n-1) - xk(1:n-1))**2) - x(n)

    end subroutine myevalc

    !******************************************************************************
    ! JACOBIAN OF THE CONSTRAINTS
    !******************************************************************************
    subroutine myevaljac(n,x,ind,jcvar,jcval,jcnnz,lim,lmem,flag)

        implicit none

        ! SCALAR ARGUMENTS
        logical, intent(out) :: lmem
        integer, intent(in) :: ind,lim,n
        integer, intent(out) :: flag,jcnnz

        ! ARRAY ARGUMENTS
        integer, intent(out) :: jcvar(lim)
        real(kind=8), intent(in) :: x(n)
        real(kind=8), intent(out) :: jcval(lim)

        integer :: i

        flag = 0
        lmem = .false.

        jcnnz = n

        if ( jcnnz .gt. lim ) then
            lmem = .true.
            return
        end if

        jcvar(1:n) = (/(i, i = 1, n)/)
        jcval(1:n) = (/(grad(ind,i) + sigma * (x(i) - xk(i)), i = 1, n-1), -1.0d0/)

    end subroutine myevaljac

    !******************************************************************************
    ! HESSIAN OF THE CONSTRAINTS
    !******************************************************************************
    subroutine myevalhc(n,x,ind,hcrow,hccol,hcval,hcnnz,lim,lmem,flag)

        implicit none

        ! SCALAR ARGUMENTS
        logical, intent(out) :: lmem
        integer, intent(in) :: ind,lim,n
        integer, intent(out) :: flag,hcnnz

        ! ARRAY ARGUMENTS
        integer, intent(out) :: hccol(lim),hcrow(lim)
        real(kind=8), intent(in) :: x(n)
        real(kind=8), intent(out) :: hcval(lim)

        flag = 0
        lmem = .false.
    
        hcnnz = n - 1
    
        if ( hcnnz .gt. lim ) then
            lmem = .true.
            return
        end if
    
        hcrow(1:n-1) = (/(i, i = 1, n-1)/)
        hccol(1:n-1) = (/(i, i = 1, n-1)/)
        hcval(1:n-1) = sigma

    end subroutine myevalhc

    ! ******************************************************************
    ! ******************************************************************

    subroutine myevalfc(n,x,f,m,c,flag)

        implicit none

        ! SCALAR ARGUMENTS
        integer, intent(in) :: m,n
        integer, intent(out) :: flag
        real(kind=8), intent(out) :: f

        ! ARRAY ARGUMENTS
        real(kind=8), intent(in) :: x(n)
        real(kind=8), intent(out) :: c(m)

        flag = - 1

    end subroutine myevalfc

    ! ******************************************************************
    ! ******************************************************************

    subroutine myevalgjac(n,x,g,m,jcfun,jcvar,jcval,jcnnz,lim,lmem,flag)

        implicit none

        ! SCALAR ARGUMENTS
        logical, intent(out) :: lmem
        integer, intent(in) :: lim,m,n
        integer, intent(out) :: flag,jcnnz

        ! ARRAY ARGUMENTS
        integer, intent(out) :: jcfun(lim),jcvar(lim)
        real(kind=8), intent(in) :: x(n)
        real(kind=8), intent(out) :: g(n),jcval(lim)

        flag = - 1

    end subroutine myevalgjac

    ! ******************************************************************
    ! ******************************************************************

    subroutine myevalgjacp(n,x,g,m,p,q,work,gotj,flag)

        implicit none

        ! SCALAR ARGUMENTS
        logical, intent(inout) :: gotj
        integer, intent(in) :: m,n
        integer, intent(out) :: flag
        character, intent(in) :: work

        ! ARRAY ARGUMENTS
        real(kind=8), intent(in) :: x(n)
        real(kind=8), intent(inout) :: p(m),q(n)
        real(kind=8), intent(out) :: g(n)

        flag = - 1

    end subroutine myevalgjacp

    ! ******************************************************************
    ! ******************************************************************

    subroutine myevalhl(n,x,m,lambda,sf,sc,hlrow,hlcol,hlval,hlnnz,lim,lmem,flag)

        implicit none

        ! SCALAR ARGUMENTS
        logical, intent(out) :: lmem
        integer, intent(in) :: lim,m,n
        integer, intent(out) :: flag,hlnnz
        real(kind=8), intent(in) :: sf

        ! ARRAY ARGUMENTS
        integer, intent(out) :: hlcol(lim),hlrow(lim)
        real(kind=8), intent(in) :: lambda(m),sc(m),x(n)
        real(kind=8), intent(out) :: hlval(lim)

        flag = - 1

    end subroutine myevalhl

    ! ******************************************************************
    ! ******************************************************************

    subroutine myevalhlp(n,x,m,lambda,sf,sc,p,hp,goth,flag)

        implicit none

        ! SCALAR ARGUMENTS
        logical, intent(inout) :: goth
        integer, intent(in) :: m,n
        integer, intent(out) :: flag
        real(kind=8), intent(in) :: sf

        ! ARRAY ARGUMENTS
        real(kind=8), intent(in) :: lambda(m),p(n),sc(m),x(n)
        real(kind=8), intent(out) :: hp(n)

        flag = - 1

    end subroutine myevalhlp
end Program main
