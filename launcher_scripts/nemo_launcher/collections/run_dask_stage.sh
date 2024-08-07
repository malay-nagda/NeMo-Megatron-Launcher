# Env vars
export RAPIDS_NO_INITIALIZE="1"
export CUDF_SPILL="1"
export DASK_DATAFRAME__QUERY_PLANNING=False

export LIBCUDF_CUFILE_POLICY=${LIBCUDF_CUFILE_POLICY:-ALWAYS}

# Start the scheduler on the rank 0 node
if [[ -z "$SLURM_NODEID" ]] || [[ $SLURM_NODEID == 0 ]]; then
  echo "Starting scheduler"
  if [[ $DEVICE == 'cpu' ]]; then
    dask scheduler \
    --scheduler-file $SCHEDULER_FILE \
    --protocol $PROTOCOL \
    --interface $INTERFACE >> $SCHEDULER_LOG 2>&1 &
  fi
  if [[ $DEVICE == 'gpu' ]]; then
    DASK_DISTRIBUTED__COMM__UCX__CREATE_CUDA_CONTEXT=True \
    DASK_DISTRIBUTED__RMM__POOL_SIZE=$RMM_SCHEDULER_POOL_SIZE \
    dask scheduler \
    --scheduler-file $SCHEDULER_FILE \
    --protocol $PROTOCOL \
    --interface $INTERFACE >> $SCHEDULER_LOG 2>&1 &
  fi
fi

# Wait for the scheduler to start
sleep 30

# Start the workers on each node
echo "Starting workers..."
export WORKER_LOG=$LOGDIR/worker_${SLURM_NODEID}-${SLURM_LOCALID}.log
if [[ $DEVICE == 'cpu' ]]; then
    dask worker \
    --scheduler-file $SCHEDULER_FILE \
    --memory-limit $CPU_WORKER_MEMORY_LIMIT \
    --nworkers $NUM_WORKERS \
    --interface $INTERFACE >> $WORKER_LOG 2>&1 &
fi
if [[ $DEVICE == 'gpu' ]]; then
    dask-cuda-worker \
    --scheduler-file $SCHEDULER_FILE \
    --rmm-pool-size $RMM_WORKER_POOL_SIZE \
    --interface $INTERFACE \
    --rmm-async >> $WORKER_LOG 2>&1 &
fi

# Wait for the workers to start
sleep 60

if [[ -z "$SLURM_NODEID" ]] || [[ $SLURM_NODEID == 0 ]]; then
  echo "Starting script"
  echo "Time Check: `date`"
  bash $RUNSCRIPT
  echo "Time Check: `date`"
  touch $DONE_MARKER
fi

# All nodes wait until done to keep the workers and scheduler active
while [ ! -f $DONE_MARKER ]
do
  sleep 15
done
