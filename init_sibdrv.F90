!---------------------------------------------------------------------
subroutine init_sibdrv( sib, time )
!---------------------------------------------------------------------

use sibtype
use timetype
use sib_const_module
use sib_io_module

!itb_crop...
use sib_bc_module
!itb_crop_end...

#include "nc_util.h"

implicit none

!---------------------------------------------------------------------
!itb...init_sibdrv reads most initialization information. takes 
!itb...place of several BUGS routines, most notably init_global.
!
!     REFERENCES:
!
! Modifications:
!  - added dtsibbcin, dtsibmetin for possible different intervals
!    of reading in the sibbc and sibdrv met data dd, jk 980209
!  Kevin Schaefer moved read IC and respfactor to after driver data (8/12/04)
!  Kevin Schaefer added calls to read NCEP1 driver data (8/13/04)
!
!     SUBROUTINES CALLED:
!          none
!     FUNCTIONS CALLED:
!          none
!
!     INCLUDED COMMONS:
!
!     ARGUMENT LIST VARIABLES
!---------------------------------------------------------------------

! parameters
type(sib_t), dimension(subcount), intent(inout) :: sib
type(time_struct), intent(inout) :: time

! local variables


integer(kind=int_kind) :: i

    print *, 'INIT_SIBDRV:'

    !itb--------------------------------------------------------
    !itb...initialize some seasonal diagnostic values...

    do i = 1, subcount
        sib(i)%diag%snow_end(1) = 365.0
        sib(i)%diag%snow_end(2) = 365.0
        sib(i)%diag%snow_end(3) = 365.0
        sib(i)%diag%tot_an(:)   = 0.0_dbl_kind
        sib(i)%diag%tot_ss(:,:)   = 0.0_dbl_kind
        sib(i)%stat%pt_num=i
    enddo    

    ! parse sib_qpopts and sib_pbpopts to see which variables are output
    call read_qp_pbp_opts
    
    ! initialize time variables
    print *, '   initialize time variables'
    call time_init( time )
    sib(:)%stat%julday = time%doy

    ! read in time-invariant boundary conditions for global runs
    print *,'   reading time-invariant boundary conditions'
    call read_ti(sib)

    ! calculate previous month's time-variant boundary conditions
    !  and read in time-invariant boundary conditions
    print *, '   obtaining previous month time-variant boundary conditions'
    call previous_bc( sib, time )

    print *, '   reading in initial conditions: ',trim(ic_path)
    call read_ic(sib,time)

   print *,'   setting soil properties '
    call soil_properties( sib )
    
    ! read in initial driver data
    print *, '   reading in initial time-step driver data'
    if ( drvr_type == 'ecmwf' ) then
        call sibdrv_read_ecmwf( sib, time )
    elseif ( drvr_type == 'ncep1' ) then
        call sibdrv_read_ncep1( sib, time )
    elseif ( drvr_type == 'ncep2' ) then
        call sibdrv_read_ncep2( sib, time )
    elseif ( drvr_type == 'geos4' ) then
        call sibdrv_read_geos4( sib, time )
    elseif ( drvr_type == 'single' ) then
        call sibdrv_read_single( sib, time )
    !kdcorbin, 02/11
    elseif ( drvr_type == 'narr' ) then
        call sibdrv_read_narr( sib, time )
    else
        stop 'Invalid drvr_type specified'
    endif

! read in respfactor file
    print *, '   reading in respFactor'
    call read_respfactor(sib)

! initialize crops (modified by kdcorbin, 02/11)
   print*,'   initializing crops'
   call init_crop( sib,time )
   call bc_interp( sib,time )

! calculate initial solar declination
    print*,'   initializing solar declination'
    call init_solar_dec( time )

end subroutine init_sibdrv
!
!=================================================
subroutine read_qp_pbp_opts
!=================================================

use sib_io_module
use sib_const_module
implicit none

integer(kind=int_kind) :: i,n
logical(kind=log_kind) :: doqptem
integer(kind=int_kind) :: ldummy, ndummy
character (len=16) :: nametem
character (len=80) :: listtem


    !-------------------------------------------------------------
    ! read sib_qpopts and count number of variables to be output
    !-------------------------------------------------------------
    open(unit=2,file=qp_path,form='formatted') !jk
    nqpsib = 0
    nqp3sib = 0
    do 
        read(2,*, end=922)doqptem,ldummy,nametem,ndummy,listtem
        if(ldummy.eq.1) then
            nqp3sib = nqp3sib + 1
        else if (ldummy.eq.0) then
            nqpsib = nqpsib + 1
        endif
    enddo

    922  continue

    rewind 2
    allocate (doqp3sib(nqp3sib))
    allocate (nameqp3sib(nqp3sib))
    allocate (listqp3sib(nqp3sib))
    allocate (numqp3sib(nqp3sib))
    allocate (doqpsib(nqpsib))
    allocate (nameqpsib(nqpsib))
    allocate (listqpsib(nqpsib))
    allocate (numqpsib(nqpsib))
    iiqp3sib = 0
    iiqpsib = 0
    do i = 1,nqp3sib+nqpsib
        read(2,*)doqptem,ldummy,nametem,ndummy,listtem
        if(ldummy.eq.1) then
            iiqp3sib = iiqp3sib + 1
            doqp3sib(iiqp3sib) = doqptem
            nameqp3sib(iiqp3sib) = nametem
            listqp3sib(iiqp3sib) = listtem
            numqp3sib(iiqp3sib) = ndummy
        else if (ldummy.eq.0) then
            iiqpsib = iiqpsib + 1
            doqpsib(iiqpsib) = doqptem
            nameqpsib(iiqpsib) = nametem
            listqpsib(iiqpsib) = listtem
            numqpsib(iiqpsib) = ndummy
        endif
    enddo 
    close(2)
    allocate (indxqp3sib(nqp3sib))
    allocate (indxqpsib(nqpsib))

    iiqpsib = 0
    do n = 1,nqpsib
        if(doqpsib(n)) then
            iiqpsib = iiqpsib + 1
            indxqpsib(n) = iiqpsib
        endif
    enddo
    iiqp3sib = 0
    do n = 1,nqp3sib
        if(doqp3sib(n)) then
            iiqp3sib = iiqp3sib + 1
            indxqp3sib(n) = iiqp3sib
        endif
    enddo
    do n = 1,nqpsib
        if(.not.doqpsib(n)) then
            indxqpsib(n) = iiqpsib + 1
        endif
    enddo
    do n = 1,nqp3sib
        if(.not.doqp3sib(n)) then
            indxqp3sib(n) = iiqp3sib + 1
        endif
    enddo


    !      initialize diagnostics         
    allocate (qpsib(subcount,iiqpsib+1))   
    allocate( qp2varid(nqpsib) )
    allocate( qp3varid(nqp3sib) )
    allocate (qp3sib(subcount,nsoil,iiqp3sib+1))   
    qp3sib(:,:,:) = 0.0
    qpsib(:,:) = 0.0
    print*,'   diagnostics initialized'



    !---------------------------------------------------------------
    ! read sib_pbpopts and count number of variables to be output
    !---------------------------------------------------------------
    open(unit=2,file=pbp_path,form='formatted')   !jk
    npbpsib = 0
    npbp2sib = 0
    
    ! count number of variables listed for pbp and pbp2 data in sib_pbpopts
    do 
        read(2,*,end=932)doqptem,ldummy,nametem,ndummy,listtem
        if(ldummy.eq.1) then
            npbp2sib = npbp2sib + 1
        else if (ldummy.eq.0) then
            npbpsib = npbpsib + 1
        endif
    enddo 

    932  continue
    rewind 2

    allocate (dopbp2sib(npbp2sib))
    allocate (namepbp2sib(npbp2sib))
    allocate (listpbp2sib(npbp2sib))
    allocate (numpbp2sib(npbp2sib))
    allocate (dopbpsib(npbpsib))
    allocate (namepbpsib(npbpsib))
    allocate (listpbpsib(npbpsib))
    allocate (numpbpsib(npbpsib))

    ! count number of variables that are set to be saved to pbp files
    iipbp2sib = 0
    iipbpsib = 0
    do i = 1,npbp2sib+npbpsib
        read(2,*)doqptem,ldummy,nametem,ndummy,listtem
        !write(*,*)doqptem,ldummy,nametem,ndummy,listtem
        if(ldummy.eq.1) then
            iipbp2sib = iipbp2sib + 1
            dopbp2sib(iipbp2sib) = doqptem
            namepbp2sib(iipbp2sib) = nametem
            listpbp2sib(iipbp2sib) = listtem
            numpbp2sib(iipbp2sib) = ndummy
        else if (ldummy.eq.0) then
            iipbpsib = iipbpsib + 1
            dopbpsib(iipbpsib) = doqptem
            namepbpsib(iipbpsib) = nametem
            listpbpsib(iipbpsib) = listtem
            numpbpsib(iipbpsib) = ndummy
        endif
    enddo 
    close(2)
    
    allocate (indxpbp2sib(npbp2sib))
    allocate (indxpbpsib(npbpsib))

    iipbpsib = 0
    do n = 1,npbpsib
        if(dopbpsib(n)) then
            iipbpsib = iipbpsib + 1
            indxpbpsib(n) = iipbpsib
        endif
    enddo
    iipbp2sib = 0
    do n = 1,npbp2sib
        if(dopbp2sib(n)) then
            iipbp2sib = iipbp2sib + 1
            indxpbp2sib(n) = iipbp2sib
        endif
    enddo
    do n = 1,npbpsib
        if(.not.dopbpsib(n)) then
            indxpbpsib(n) = iipbpsib + 1
        endif
    enddo
    do n = 1,npbp2sib
        if(.not.dopbp2sib(n)) then
            indxpbp2sib(n) = iipbp2sib + 1
        endif
    enddo

    allocate( pbpsib(iipbpsib+1,ijtlensib) )
    allocate( pbpvarid(npbpsib) )
    allocate( pbp2sib(nsoil,iipbp2sib+1,ijtlensib) )
    allocate( pbp2varid(npbp2sib) )
    pbpsib(:,:) = 0.0
    pbp2sib(:,:,:) = 0.0

end subroutine read_qp_pbp_opts
!
!=================================================
subroutine read_ic(sib,time)
!=================================================
!  Author:  Ian Baker
!  Modified by:  Owen Leonard
!  Date :  March 30, 2004
!  Purpose:
!    This subroutine reads in the initial conditions file and pulls out
!  only those points in the subdomain
!
! Modifications:
!  Kevin Schaefer moved soil layer calculations to soil_properties (10/27/04)
!=================================================

use netcdf 
use typeSizes
use kinds
use sibtype
use timetype
use sib_const_module
use sib_io_module

! parameters
type(sib_t), dimension(subcount), intent(inout) :: sib
type(time_struct), intent(inout) :: time
! netcdf variables
integer(kind=int_kind) :: ncid
integer(kind=int_kind) :: varid

! local variables
integer(kind=int_kind) :: i,j,k
integer(kind=int_kind) :: nsibt
integer(kind=int_kind) :: nsoilt
integer(kind=int_kind) :: nsnowt
real(kind=int_kind) :: versiont
integer(kind=int_kind), dimension(2) :: start
integer(kind=int_kind), dimension(2) :: finish
real(kind=dbl_kind), dimension(nsib) :: ta
real(kind=dbl_kind), dimension(nsib) :: tc

!Crop Variables (modified by kdcorbin, 02/11)
integer(kind=int_kind), dimension(nsib) :: pd
integer(kind=int_kind), dimension(nsib) :: emerg_d,ndf_opt,nd_emerg

real(kind=dbl_kind), dimension(nsib) :: ta_bar, tempf
real(kind=dbl_kind), dimension(nsib) :: assim_d
real(kind=dbl_kind), dimension(nsib) :: rstfac_d
real(kind=dbl_kind),dimension(nsib) :: gdd
real(kind=dbl_kind),dimension(nsib) :: w_main
real(kind=dbl_kind), dimension(nsib,4) :: cum_wt
real(kind=dbl_kind), dimension(nsib,4) :: cum_drywt
!End Crop Variables

integer(kind=int_kind), dimension(nsib) :: nsl
real(kind=dbl_kind), dimension(nsib) :: pco2ap
real(kind=dbl_kind), dimension(nsib) :: d13cca
real(kind=dbl_kind), dimension(nsib) :: snow_veg
real(kind=dbl_kind), dimension(nsib) :: snow_age
real(kind=dbl_kind), dimension(nsib) :: snow_depth
real(kind=dbl_kind), dimension(nsib) :: snow_mass
real(kind=dbl_kind), dimension(nsib) :: tke
real(kind=dbl_kind), dimension(nsib) :: sha
real(kind=dbl_kind), dimension(nsib) :: capac1
real(kind=dbl_kind), dimension(nsib) :: capac2
real(kind=dbl_kind), dimension(nsib) :: coszbar
real(kind=dbl_kind), dimension(nsib) :: dayflag
real(kind=dbl_kind), dimension(12,nsib) :: tot_an
real(kind=dbl_kind), dimension(nsib,6) :: rst
real(kind=dbl_kind), dimension(nsib,-nsnow+1:nsoil) :: deept
real(kind=dbl_kind), dimension(nsib,-nsnow+1:nsoil) :: www_liq
real(kind=dbl_kind), dimension(nsib,-nsnow+1:nsoil) :: www_ice
real(kind=dbl_kind), dimension(nsib,nsnow) :: nz_snow
real(kind=dbl_kind), dimension(nsib,nsnow) :: lz_snow
real(kind=dbl_kind), dimension(nsib,nsnow) :: dz_snow
real(kind=dbl_kind), dimension(12,nsib,nsoil) :: tot_ss

integer(kind=int_kind),dimension(11) :: map_totals
integer(kind=int_kind)               :: jday

DATA map_totals/31,59,90,120,151,181,212,243,273,304,334/

    ! read in initial conditions (restart file)
    CHECK( nf90_open( trim(ic_path), nf90_nowrite, ncid ) )

    print *,'      opening ic file', trim(ic_path)

    !itb...read some scalars
    ENSURE_VAR( ncid, 'nsib', varid )
    CHECK( nf90_get_var( ncid, varid, nsibt ) )
    !print *, '   nsib=',nsib, ' total nsib=',nsibt
    if(nsib /= nsibt) stop'INITIAL CONDITIONS: NSIB INCORRECT'

    ENSURE_VAR( ncid, 'nsoil', varid )
    CHECK( nf90_get_var( ncid, varid, nsoilt ) )
    if(nsoil /= nsoilt) stop'INITIAL CONDITIONS: NSOIL INCORRECT'

    ENSURE_VAR( ncid, 'nsnow', varid )
    CHECK( nf90_get_var( ncid, varid, nsnowt ) )
    if(nsnow /= nsnowt) stop'INITIAL CONDITIONS: NSNOW INCORRECT'

!    ENSURE_VAR( ncid, 'subcount', varid )
!    CHECK( nf90_get_var( ncid, varid, subcountt ) )
!    if(subcount /= subcountt) stop'INITIAL CONDITIONS: SUBCOUNT INCORRECT'

    ENSURE_VAR( ncid, 'version', varid )
    CHECK( nf90_get_var( ncid, varid, versiont ) )

    ENSURE_VAR( ncid, 'nsecond', varid )
    CHECK( nf90_get_var( ncid, varid, nsecond ) )
    if(nsecond /= time%sec_year) stop 'NSECONDS DOES NOT MATCH STARTTIME'

    !itb...read nsib vectors

    ENSURE_VAR( ncid, 'ta', varid )
    CHECK( nf90_get_var( ncid, varid, ta ) )

    ENSURE_VAR( ncid, 'tc', varid )
    CHECK( nf90_get_var( ncid, varid, tc ) )
    ENSURE_VAR( ncid, 'nsl', varid )
    CHECK( nf90_get_var( ncid, varid, nsl ) )

    ENSURE_VAR( ncid, 'pco2a', varid )
    CHECK( nf90_get_var( ncid, varid, pco2ap ) )

    ENSURE_VAR( ncid, 'd13cca', varid )
    CHECK( nf90_get_var( ncid, varid, d13cca ) )

    ENSURE_VAR( ncid, 'snow_veg', varid )
    CHECK( nf90_get_var( ncid, varid, snow_veg ) )

    ENSURE_VAR( ncid, 'snow_age', varid )
    CHECK( nf90_get_var( ncid, varid, snow_age ) )

    ENSURE_VAR( ncid, 'snow_depth', varid )
    CHECK( nf90_get_var( ncid, varid, snow_depth ) )

    ENSURE_VAR( ncid, 'snow_mass', varid )
    CHECK( nf90_get_var( ncid, varid, snow_mass ) )

    ENSURE_VAR( ncid, 'tke', varid )
    CHECK( nf90_get_var( ncid, varid, tke ) )

    ENSURE_VAR( ncid, 'sha', varid )
    CHECK( nf90_get_var( ncid, varid, sha ) )

    !itb...read some 2-d vars
    ENSURE_VAR( ncid, 'td', varid )
    CHECK( nf90_get_var( ncid, varid, deept ) )

    ENSURE_VAR( ncid, 'www_liq', varid )
    CHECK( nf90_get_var( ncid, varid, www_liq ) )

    ENSURE_VAR( ncid, 'www_ice', varid )
    CHECK( nf90_get_var( ncid, varid, www_ice ) )

    !itb...now the rest...
    ENSURE_VAR( ncid, 'capac1', varid )
    CHECK( nf90_get_var( ncid, varid, capac1 ) )

    ENSURE_VAR( ncid, 'capac2', varid )
    CHECK( nf90_get_var( ncid, varid, capac2 ) )

    ENSURE_VAR( ncid, 'coszbar', varid )
    CHECK( nf90_get_var( ncid, varid, coszbar ) )

    ENSURE_VAR( ncid, 'dayflag', varid )
    CHECK( nf90_get_var( ncid, varid, dayflag ) )

    ENSURE_VAR( ncid, 'rst', varid )
    CHECK( nf90_get_var( ncid, varid, rst ) )

    !Crop Variables (modified by kdcorbin, 01/11)

    ENSURE_VAR( ncid, 'pd', varid )
    CHECK( nf90_get_var( ncid, varid, pd ) )

    ENSURE_VAR( ncid, 'emerg_d', varid )
    CHECK( nf90_get_var( ncid, varid, emerg_d ) )

    ENSURE_VAR( ncid, 'ndf_opt', varid )
    CHECK( nf90_get_var( ncid, varid, ndf_opt ) )

    ENSURE_VAR( ncid, 'nd_emerg', varid )
    CHECK( nf90_get_var( ncid, varid, nd_emerg ) )

    if (nf90_inq_varid(ncid, 'ta_bar', varid) == nf90_noerr) then
       CHECK( nf90_get_var( ncid, varid, ta_bar ) )
    else !XXX backwards compat
       ENSURE_VAR( ncid, 'tempf', varid )
       CHECK( nf90_get_var( ncid, varid, tempf) )
       ta_bar = (tempf - 32.0) / 1.8 + 273.15
    endif

    ENSURE_VAR( ncid, 'assim_d', varid )
    CHECK( nf90_get_var( ncid, varid, assim_d ) )

    ENSURE_VAR( ncid, 'rstfac_d', varid )
    CHECK( nf90_get_var(ncid, varid, rstfac_d ) )

    ENSURE_VAR( ncid, 'gdd', varid )
    CHECK( nf90_get_var( ncid, varid, gdd ) )

    ENSURE_VAR( ncid, 'w_main', varid )
    CHECK( nf90_get_var( ncid, varid, w_main ) )

    ENSURE_VAR( ncid, 'cum_wt', varid )
    CHECK( nf90_get_var( ncid, varid,cum_wt ) )

    ENSURE_VAR( ncid, 'cum_drywt', varid )
    CHECK( nf90_get_var( ncid, varid, cum_drywt ) )
    !End Crop Vars

    print*,'      reading in slabs...'

    !itb...don't know how to read slabs directly into the structure yet...
    start(1) = 1
    start(2) = 1
    finish(1) = nsib
    finish(2) = nsnow
    ENSURE_VAR( ncid, 'dzsnow', varid )
    CHECK( nf90_get_var( ncid, varid, dz_snow, start, finish ) )

    ENSURE_VAR( ncid, 'lzsnow', varid )
    CHECK( nf90_get_var( ncid, varid, lz_snow, start, finish ) )

    ENSURE_VAR( ncid, 'nzsnow', varid )
    CHECK( nf90_get_var( ncid, varid, nz_snow, start, finish ) )

    ! read in tot_an and tot_ss for rolling respfactor
    ENSURE_VAR( ncid, 'tot_an', varid )
    CHECK( nf90_get_var( ncid, varid, tot_an ) )
    ENSURE_VAR( ncid, 'tot_ss', varid )
    CHECK( nf90_get_var( ncid, varid, tot_ss ) )

    !itb...close the file
    CHECK( nf90_close( ncid ) )

    print *,'      load data into the structure'

    !itb...need to load these data into sibtype arrays
    do i = 1,subcount
        sib(i)%prog%ta = ta(subset(i))
        sib(i)%prog%tc = tc(subset(i))
        sib(i)%prog%nsl = nsl(subset(i))
        sib(i)%prog%pco2ap = pco2ap(subset(i))
        sib(i)%prog%d13cca = d13cca(subset(i))
        sib(i)%prog%snow_veg = snow_veg(subset(i))
        sib(i)%prog%snow_age = snow_age(subset(i))
        sib(i)%prog%snow_depth = snow_depth(subset(i))
        sib(i)%prog%snow_mass = snow_mass(subset(i))
        sib(i)%prog%tke = max( tkemin, tke(subset(i)) )
        sib(i)%prog%sha = sha(subset(i))
        sib(i)%stat%coszbar = coszbar(subset(i))
        sib(i)%stat%dayflag = dayflag(subset(i))
        
        sib(i)%prog%capac(1) = capac1(subset(i))
        sib(i)%prog%capac(2) = capac2(subset(i))
        
     !Crop Variables (modified by kdcorbin, 02/11)
        sib(i)%diag%pd = pd(subset(i))
        sib(i)%diag%emerg_d = emerg_d(subset(i))
        sib(i)%diag%ndf_opt = ndf_opt(subset(i))
        sib(i)%diag%nd_emerg = nd_emerg(subset(i))

        sib(i)%diag%ta_bar = ta_bar(subset(i))
        sib(i)%diag%assim_d = assim_d(subset(i))
        sib(i)%diag%rstfac_d = rstfac_d(subset(i))
        sib(i)%diag%gdd = gdd(subset(i))
        sib(i)%diag%w_main = w_main(subset(i))

        do j=1,4
           if (cum_drywt(subset(i),j) < 0.) then
              sib(i)%diag%cum_wt(j) = 0.001
              sib(i)%diag%cum_drywt(j) = 0.001
           else
               sib(i)%diag%cum_wt(j) = cum_wt(subset(i),j)
               sib(i)%diag%cum_drywt(j) = cum_drywt(subset(i),j)    
          endif
        enddo

        if(sib(i)%diag%ndf_opt > 0) sib(i)%diag%ndf_opt=sib(i)%diag%ndf_opt-1
 
        !kdcorbin, 03/11 - added pd_annual
        if(sib(i)%diag%pd > 0) then 
           sib(i)%diag%pd_annual=1
        else
           sib(i)%diag%pd_annual=0
        endif
        if(sib(i)%diag%gdd > 100.0 ) sib(i)%diag%phen_switch = 1
      !End crop vars

        do k = 1, 12
            sib(i)%diag%tot_an(k) = tot_an(k,subset(i))

            do j = 1, nsoil
                sib(i)%diag%tot_ss(k,j) = tot_ss(k,subset(i),j)
            enddo
        enddo

        do j = 1, 6
            sib(i)%prog%rst(j) = rst(subset(i),j)
        enddo

        do j = 1,nsnow
            k = j - 5
            sib(i)%prog%dz(k)      = dz_snow(subset(i),j)
            sib(i)%prog%node_z(k)  = nz_snow(subset(i),j)
            sib(i)%prog%layer_z(k-1) = lz_snow(subset(i),j)
        enddo

        do j=-nsnow+1,nsoil
            sib(i)%prog%td(j)      = deept(subset(i),j)
            sib(i)%prog%www_liq(j) = www_liq(subset(i),j)
            sib(i)%prog%www_ice(j) = www_ice(subset(i),j)
        enddo

    enddo   !subcount loop

    !print *, '     read in sib initial conditions'

!itb...need to manipulate tot_an and tot_ss for restart/initial conditions...
    if(time%sec_year /= 0) then
       jday = nsecond/86400
       month_loop: do j = 1, 11
         if(jday == map_totals(j)) then
           do i=1,subcount
             sib(i)%diag%tot_ss(j+1:13,:) = 0.0_dbl_kind
             sib(i)%diag%tot_an(j+1:13)   = 0.0_dbl_kind
           enddo
           exit month_loop
         endif
       enddo month_loop

    else

     do i=1,subcount
       sib(i)%diag%tot_ss(:,:) = 0.0_dbl_kind
       sib(i)%diag%tot_an(:)   = 0.0_dbl_kind
     enddo

    endif

end subroutine read_ic

!===============================================
subroutine read_respfactor(sib)
!===============================================
! reads in a respfactor from an external file
!
! Modifications:
!  Kevin Schaefer filled in respfactor for any error (status/=0 rather than status>0) (11/11/04)
!
use kinds
use sibtype
use sib_const_module
use sib_io_module
implicit none

! parameters
type(sib_t), dimension(subcount), intent(inout) :: sib

! local variables
integer(kind=int_kind) :: i,j
integer(kind=int_kind) :: status
real(kind=dbl_kind), dimension(nsib,nsoil) :: respfactor


    !     Read the SiB-CO2 respiration factor 
    if(drvr_type=='single')then
        open( unit=3, file=co2_path, form='formatted', status='old', iostat=status) !jk
        do i = 1,nsoil
            read( 3,*, iostat = status ) respfactor(1,i)
        enddo
    else
        open( unit=3, file=co2_path, form='unformatted', status='old', iostat=status )
        read( unit=3, iostat=status ) i
        read( unit=3, iostat=status ) j
        read( unit=3, iostat=status ) respfactor(:,:)
    endif
    close(unit=3)

    if ( status /= 0 ) then
        print *, '      error reading in respFactor'
        print *, '      respFactor set globally to 3.0e-6'
        do i=1,nsib
            do j=1,nsoil
                respfactor(i,j) = 3.0e-6_dbl_kind
            enddo
        enddo
    endif

    !itb...copy respfactor into the structure...
    do i=1,subcount
        do j=1,nsoil
            sib(i)%param%respfactor(j) = respfactor(subset(i),j)
        enddo
    enddo

end subroutine read_respfactor
!
!================================================
subroutine soil_properties(sib)
!================================================
! calculates various soil parameters that do not change with time
!
! Modifications:
!  Kevin Schaefer moved soil layer calculates here from read_ic (10/27/04)
!===============================================================================
!
use kinds
use sibtype
use sib_const_module
implicit none

! parameters
type(sib_t), dimension(subcount), intent(inout) :: sib

! local variables
integer(kind=int_kind) :: i, j      ! (-) indeces
real(kind=real_kind) :: tkm        ! (W/m K) mineral conductivity
real(kind=real_kind) :: bd         ! (kg/m^3) bulk density of dry soil material
real(kind=real_kind) :: kroot(12)  ! (?) root density extinction coeficient
real(kind=real_kind) :: totalroot  ! (?) total root density in soil column
real(kind=real_kind) :: ztop       ! (-) normalized depth of soil layer top
real(kind=real_kind) :: zbot       ! (-) normalized depth of soil layer bottom

real(kind=real_kind) :: pot_fc     ! water potential at field capacity (J/kg)
real(kind=real_kind) :: pot_wp     ! water potential at wilt point (J/kg)

integer(kind=int_kind) :: temp_biome


!
! assign values of root density profiles
DATA KROOT/3.9,3.9,2.0,5.5,5.5,2.0,5.5,2.0,2.0,5.5,2.0,5.5/


    do i = 1,subcount

!itb_crop...
      if(sib(i)%param%biome >= 20.0) then
         temp_biome = 12
      else
         temp_biome = int(sib(i)%param%biome)
      endif



        !Bio-----------------------------------------------------------
        !Bio   miscellaneous soil properties
        !Bio------------------------------------------------------------


!itb...fixing field capacity and wilting point, based on %sand/%clay basis
!itb...the stress performance is directly tied to FC and WP values. We are
!itb...playing with the 'operating range' that gives us the best model 
!itb...performance. 

        pot_fc = -15.0   ! field capacity (J/kg)

        pot_wp = -1500.0 ! wilt point (J/kg)

        sib(i)%param%fieldcap = sib(i)%param%poros*             &
                   ((pot_fc/9.8)/sib(i)%param%phsat) ** (-1.0 / sib(i)%param%bee)

        sib(i)%param%vwcmin = sib(i)%param%poros *               &
                 ((pot_wp/9.8)/sib(i)%param%phsat) ** (-1.0 / sib(i)%param%bee)


        
        tkm = ( 8.80*sib(i)%param%sandfrac + 2.92*sib(i)%param%clayfrac ) /    &
            ( sib(i)%param%sandfrac + sib(i)%param%clayfrac )

        bd = (1.0 - sib(i)%param%poros) * 2.7E3

        do j=1,nsoil

            sib(i)%param%tkmg(j)    = tkm**(1.0 - sib(i)%param%poros)

            sib(i)%param%tksatu(j)  = sib(i)%param%tkmg(j) * 0.57**sib(i)%param%poros 

            sib(i)%param%tkdry(j)   = (0.135*bd + 64.7) / (2.7E3 - 0.947*bd)

            sib(i)%param%csolid(j)  = (2.128*sib(i)%param%sandfrac       &
                + 2.385*sib(i)%param%clayfrac)/      &
                (sib(i)%param%sandfrac + sib(i)%param%clayfrac)*1.0E6
        enddo

        !Bio-------------------------------------------------------------
        !Bio  compute soil layer values
        !Bio-------------------------------------------------------------

        !itb...CLM uses a 'scalez' (0.025) factor to determine soil layer depths. 
        !itb...for now i'm going to use it as well...
        do j=1,nsoil
            sib(i)%prog%node_z(j) = 0.025*(exp(0.5*(j-0.5))-1.0)
        enddo

        sib(i)%prog%dz(1) = 0.5*(sib(i)%prog%node_z(1)+sib(i)%prog%node_z(2))

        do j=2,nsoil-1
            sib(i)%prog%dz(j) = 0.5*(sib(i)%prog%node_z(j+1)-  &
                sib(i)%prog%node_z(j-1))
        enddo

        sib(i)%prog%dz(nsoil) = sib(i)%prog%node_z(nsoil) -   &
            sib(i)%prog%node_z(nsoil-1)
        sib(i)%prog%layer_z(0) = 0.0

        do j=1,nsoil-1
            sib(i)%prog%layer_z(j) = 0.5*(sib(i)%prog%node_z(j) +   &
                sib(i)%prog%node_z(j+1))
        enddo
        sib(i)%prog%layer_z(nsoil) = sib(i)%prog%node_z(nsoil) +    &
            0.5*sib(i)%prog%dz(nsoil)


!itb...seems like I'm always wanting info about soil layers...
!        do j=1,nsoil
!          print'(i5,3f15.5)',j,sib(i)%prog%layer_z(j),sib(i)%prog%node_z(j), &
!                sib(i)%prog%dz(j)
!        enddo
!        stop

        !Bio-------------------------------------------------------------
        !Bio   compute root fractions for each layer
        !Bio-------------------------------------------------------------
!
! total roots
        totalroot = (1.0 - exp(-kroot(temp_biome)*     &
          sib(i)%prog%layer_z(nsoil))) / kroot(temp_biome)
!
! root fraction per soil layer
        ztop = 0.0
        do j=1,nsoil
            zbot = ztop + sib(i)%prog%dz(j)
            sib(i)%param%rootf(j) = (exp(-kroot(temp_biome)*ztop) &
                - exp(-kroot(temp_biome)*zbot))/ &
                (kroot(temp_biome) * totalroot)

            ztop = zbot

        enddo


        !itb...quick patch to cover some underflow problems...
        if(sib(i)%param%vcover < sib(i)%param%zlt/10.0)  then
            sib(i)%param%vcover = sib(i)%param%vcover * 10.0
        endif
    enddo  ! subcount loop

      !kdcorbin, 02/11 - commenting www_liq reset
      !EL...make each layer in biome 12 has 95% saturation for initialization 
      !relevant to NACP  site interim syn
      !if (temp_biome==12) then 
      !    do j = 1,nsoil 
      !       sib%prog%www_liq(j) = (sib%param%poros * &  
      !               sib%prog%dz(j) * denh2o) * 0.95 

             ! EL...The above formulation was based on wfrac calculation in respsib.F90
             !EL...wfrac(j) = 0.95= sib%prog%www_liq(j) / (sib%prog%dz(j) * 
             !EL...       sib%param%poros * denh2o) 
      !    enddo
      !endif 

end subroutine soil_properties
