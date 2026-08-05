function reports = check_generated_problem_definitions()
%CHECK_GENERATED_PROBLEM_DEFINITIONS Verify all generated problem modules.
%
% Generated modules are treated as disposable build outputs. This checker
% writes them into temporary folders so the maintained EXAMPLES tree remains
% free of per-example generated_problem/ artifacts.

repoRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(repoRoot));

cases = {
    @define_problem_LV,             fullfile(repoRoot, 'EXAMPLES', 'LV')
    @define_problem_SIR,            fullfile(repoRoot, 'EXAMPLES', 'SIR')
    @define_problem_AP,             fullfile(repoRoot, 'EXAMPLES', 'AP')
    @define_problem_NFKB,           fullfile(repoRoot, 'EXAMPLES', 'NFKB')
    @define_problem_LinearCascade,  fullfile(repoRoot, 'EXAMPLES', 'LinearCascade')
    @define_problem_LinearCascade3, fullfile(repoRoot, 'EXAMPLES', 'LinearCascade')
};

reports = cell(size(cases, 1), 1);
tempDirs = cell(size(cases, 1), 1);
for i = 1:size(cases, 1)
    defineProblem = cases{i, 1};
    legacyDir = cases{i, 2};
    problem = defineProblem();
    tempDirs{i} = tempname;
    generatedDir = fullfile(tempDirs{i}, 'generated_problem');
    mkdir(tempDirs{i});
    cleanupDir = onCleanup(@() removeTempDir(tempDirs{i}));
    reports{i} = cuqdyn_check_generated_problem_modules(problem, legacyDir, generatedDir);
    clear cleanupDir
end
reports = vertcat(reports{:});

fprintf('All generated problem modules match their legacy files.\n');
end

function removeTempDir(folderPath)
if exist(folderPath, 'dir')
    rmdir(folderPath, 's');
end
end
