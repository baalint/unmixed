function [EEG] = um_mmfit(EEG,input,varargin)
% Mixed model fit
[cfg] = finputcheck(varargin,...
    {'channel','integer',[],1;...
    'fitMethod','string',{'ML','REML'},'ML';...
    'initstats','boolean',[],1;... %in case only betas are necessary, do not do initstats.
    'optimizer','string',{'fminunc','quasinewton','fminsearch','bobyqa'},'quasinewton';...
    'covariance','string',{'Diagonal','Full','FullCholesky','CompSymm'},'FullCholesky'; ...
    },'mode','ignore');
if ischar(cfg)
    error(cfg)
end


if isstruct(input{1})
    
    % select channel
    %     for k = 1:length(input)
    %         input{k}= pop_select(input{k},'channel',cfg.channel);
    %     end
    data = cellfun(@(x)squeeze(x.data(cfg.channel,:,:)),input,'UniformOutput',0);
    
elseif ischar(input)
    % read input files
    for k = 1:length(input)
        input{k} = pop_loadset('filename',input{k},'loadmode',cfg.channel);
    end
    data = cellfun(@(x)x.data,input,'UniformOutput',0);
end

%% Prepare Data


X = EEG.unmixed.uf_fixef.Xdc;
Y = double(cat(2,data{:})');
tmp = cellfun(@(x)x.Zdc,EEG.unmixed.uf_ranef,'UniformOutput',0);
Z = cat(2,tmp{:});
GPU = 1;

%% Generate Covariance Matrices
fprintf('um_mmfit: initializing random effect covariance matrix structures\n')
% different variables that we need to generate the matrix
nTimeshifts = length(EEG.unmixed.uf_ranef{1}.times);
levelsPerGroup = cellfun(@(x)length(unique(x.Zdc_level2cols)),EEG.unmixed.uf_ranef);
factorsXPerGroup= cellfun(@(x)size(x.X,2)-1,EEG.unmixed.uf_ranef);% minus one because we have the dummy grouping variable included


% We need to know how many entries "Each timeshift of each grouping variable" has

Glevels = [];
timeshifts = [];
groupid = [];
for g = 1:length(levelsPerGroup)
    Glevels = [Glevels repmat(levelsPerGroup(g),1,nTimeshifts)];
    groupid = [groupid repmat(g,1,nTimeshifts)];
    timeshifts = [timeshifts 1:nTimeshifts]; % for the label
end

% Each Timeshift/Grouping gets their own independent covariance matrix (for
% now...) that are then combined to a block-covariance structure.
mat = [];
for i = 1:length(Glevels)
    g = groupid(i);
    groupname = EEG.unmixed.uf_ranef{g}.ranefgrouping;
    timeshift = EEG.unmixed.uf_ranef{g}.times(timeshifts(g));
    % each timepoint / group has how many entries?
    
    mat{i} = classreg.regr.lmeutils.covmats.CovarianceMatrix.createCovariance(cfg.covariance,factorsXPerGroup(g),...
        'VariableNames',EEG.unmixed.uf_ranef{g}.colnames(1:end-1),'Name',sprintf('g:%s-t:%.3f',groupname,timeshift));
    
end
% Generate one covariance matrix out of many
Psi = classreg.regr.lmeutils.covmats.BlockedCovariance(mat,Glevels);


%% Run the matlab LMM solver
ix = any(X,2);


dostats = false; % this will be very slow, in order to generate Confidence Intervals. We have to see whether we a) can speed it up or b) ignore it...

fprintf('um_mmfit: Starting with model fit \n')
tic
% this ensures that our overwritting rank function is removed even on ctrl+c
cleanupObj = onCleanup(@cleanMeUp);
addpath(fullfile('src','um_toolbox','temporaryFunctions','rank'))

% if GPU
%    X = gpuArray(X);
%    Y = gpuArray(Y);
%    Z = gpuArray(Z);
% end

switch cfg.optimizer
    case 'quasinewton'
        optimizeroptions = statset('LinearMixedModel');
%         optimizeroptions.MaxIter = 10000;
        optimizeroptions.Display = 'Iter';
%         optimizeroptions.MaxFunEvals = 40000;
        model = classreg.regr.lmeutils.StandardLinearMixedModel(X(ix,:),Y(ix),Z(ix,:),Psi,...
            cfg.fitMethod,true,dostats,'Optimizer','quasinewton','OptimizerOptions',optimizeroptions,'CheckHessian',1);
    case 'fminunc'
        model = classreg.regr.lmeutils.StandardLinearMixedModel(X(ix,:),Y(ix),Z(ix,:),Psi,...
            cfg.fitMethod,true,dostats,'Optimizer','fminunc','OptimizerOptions',optimoptions('fminunc','Display','Iter','MaxFunctionEvaluations',40000),'CheckHessian',1);
    case 'bobyqa'
        % the bobyqa solver, the option "fminsearch" is just to fool the
        % matlab internal mixed model functions. Bobyqa is hardcoded in
        % um_customlinearmixedmodel (the name is not
        % um_CustomBobyqaMixedModel because I want to try other optimizers
        % too)
        model = um_CustomLinearMixedModel(X(ix,:),Y(ix),Z(ix,:),Psi,...
            cfg.fitMethod,true,dostats,'Optimizer','fminsearch','OptimizerOptions',struct('MaxFunEvals',40000),'CheckHessian',1);

    case 'fminsearch'
        model = classreg.regr.lmeutils.StandardLinearMixedModel(X(ix,:),Y(ix),Z(ix,:),Psi,...
            cfg.fitMethod,true,dostats,'Optimizer','fminsearch','OptimizerOptions',struct('MaxFunEvals',40000),'CheckHessian',1);
end
rmpath(genpath(fullfile('src','um_toolbox','temporaryFunctions')))
toc



if cfg.initstats
    fprintf('Calculating SE and the likes, this step takes quite some time ... ')
    model = model.initstats;
    fprintf(' done\n')
end
EEG.unmixed.modelfit = model;
end

function cleanMeUp()
rmpath(fullfile('src','um_toolbox','temporaryFunctions','rank'))
end
