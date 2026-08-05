function cuq_parpool()
% Start a parallel pool if none is running; report worker count either way.
currentPool = gcp('nocreate');
if isempty(currentPool)
    numWorkers = max(parcluster('local').NumWorkers - 1, 1);
    try
        parpool('local', numWorkers);
        fprintf('Started parallel pool with %d workers.\n', numWorkers);
    catch ME
        warning('Failed to start parallel pool. Running sequentially. Error: %s', ME.message);
    end
else
    fprintf('Parallel pool already running with %d workers.\n', currentPool.NumWorkers);
end
end
