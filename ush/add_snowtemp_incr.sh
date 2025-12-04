#! /usr/bin/env bash

#-------------------------------------------------------------------------------------------------
# Script to add snow temperature increments
# Clara Draper, April 2025.
#-------------------------------------------------------------------------------------------------

export PGMOUT=${PGMOUT:-${pgmout:-'&1'}}
export PGMERR=${PGMERR:-${pgmerr:-'&2'}}
export REDOUT=${REDOUT:-'1>'}
export REDERR=${REDERR:-'2>'}

APPLYINCR_EXEC=${EXECgfs}/gdas_apply_incr.x

export PGM=${APPLYINCR_EXEC}
export pgm=${PGM}

NMEM_INCR=${NMEM_ENS:-1}
CASE=${CASE:-${CASE_ENS}}
LFHR=${LFHR:-6}

NPROC_INCR=6 # Yanjun, this can be increased if it's slow ( I think this will be enough )

# yanjun - if you have a more recent version of the apply_incr code, 
# you may need to update the namelist

# write namelist
cat << EOF > apply_incr_nml
&noahmp_snow
 date_str=${bPDY}
 hour_str=${bcyc}
 res=${CASE:1}
 frac_grid=$FRAC_GRID
 orog_path="${DATA}"
 otype="${CASE}.mx${OCNRES}_oro_data"
 rst_path="${DATA}"
 inc_path="${DATA}"
/
EOF

# input orog files
for n in $(seq 1 "${ntiles}"); do
    cpfs "${FIXorog}/${CASE}/${CASE}.mx${OCNRES}_oro_data.tile${n}.nc" \
            "${DATA}/${CASE}.mx${OCNRES}_oro_data.tile${n}.nc"
done

if (( LFHR >= 0 )); then 
    snowinc_fhrs=("${LFHR}")
else # construct restart times for deterministic member
    snowinc_fhrs=("${assim_freq}") # increment file at middle of window 
    if [[ "${DOIAU:-}" == "YES" ]]; then  # Update surface restarts at beginning of window
        half_window=$(( assim_freq / 2 ))
        snowinc_fhrs+=("${half_window}")
    fi
fi 

for imem in $(seq 1 "${NMEM_INCR}"); do
    if (( NMEM_INCR > 1 )); then
        cmem=$(printf %03i "${imem}")
        memchar="mem${cmem}"

        MEMDIR=${memchar} YMD=${PDY} HH=${cyc} declare_from_tmpl \
            COMOUT_ATMOS_ANALYSIS_MEM:COM_ATMOS_ANALYSIS_TMPL

        MEMDIR=${memchar} YMD=${PDY} HH=${cyc} declare_from_tmpl \
            COMOUT_ATMOS_RESTART_MEM:COM_ATMOS_RESTART_TMPL
    fi

    for FHR in "${snowinc_fhrs[@]}"; do
        for n in $(seq 1 $ntiles); do
            cpfs "${COMOUT_ATMOS_ANALYSIS_MEM}/increment.sfc.i00${FHR}.tile${n}.nc" \
                    "${DATA}/snowinc.${bPDY}.${bcyc}0000.sfc_data.tile${n}.nc"

            cpfs "${COMOUT_ATMOS_RESTART_MEM}/${bPDY}.${bcyc}0000.sfcanl_data.tile${n}.nc" \
                    "${DATA}/${bPDY}.${bcyc}0000.sfc_data.tile${n}.nc"

            # for now, save a copy of the surface analysis produced by gcycle.
            cpfs "${COMOUT_ATMOS_RESTART_MEM}/${bPDY}.${bcyc}0000.sfcanl_data.tile${n}.nc" \
                    "${COMOUT_ATMOS_RESTART_MEM}/${bPDY}.${bcyc}0000.gcycle_sfcanl_data.tile${n}.nc"
        done

        echo "calling apply snow increment $memchar" 
        srun '--export=ALL' -n ${NPROC_INCR} "${APPLYINCR_EXEC}" "${REDOUT}${PGMOUT}" "${REDERR}${PGMERR}"

        for n in $(seq 1 $ntiles); do
            cpfs "${DATA}/${bPDY}.${bcyc}0000.sfc_data.tile${n}.nc" \
                    "${COMOUT_ATMOS_RESTART_MEM}/${bPDY}.${bcyc}0000.sfcanl_data.tile${n}.nc"
        done 
    done
done

exit 0
