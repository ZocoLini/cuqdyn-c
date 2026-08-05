function report = check_generated_LV_problem()
%CHECK_GENERATED_LV_PROBLEM Verify generated LV modules match legacy modules.

thisDir = fileparts(mfilename('fullpath'));
repoRoot = fullfile(thisDir, '..', '..');
tmpDir = tempname;
genDir = fullfile(tmpDir, 'generated_problem');
mkdir(tmpDir);
cleanupDir = onCleanup(@() removeTempDir(tmpDir));

addpath(genpath(repoRoot));
problem = define_problem_LV();
report = cuqdyn_check_generated_problem_modules(problem, thisDir, genDir);
end

function removeTempDir(folderPath)
if exist(folderPath, 'dir')
    rmdir(folderPath, 's');
end
end
