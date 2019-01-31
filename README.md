# Unfold + Mixed Models = unmixed

Deconvolution, non linear modeling and Mixed Modeling toolbox

Specify ```y~1 + A + (1 + A|subject) + (1+C|image)``` Item and Subject Effects!


Minimal Example:

```

rng(1)
input = [];
for k = 1:30
    input{k} = simulate_data_lmm('noise',10,...
        'srate',50,'datasamples',600*50,...
        'basis','dirac');
end


EEG = um_designmat(input,'eventtypes','fixation','formula','y~1+A+(1+A|subject)');

EEG= um_timeexpandDesignmat(EEG,'timelimits',[-0.1,0.5]);

# Currently I recommend the bobyqa optimizer. Seems to be faster
model_fv = um_mmfit(EEG,input,'channel',1,'optimizer','bobyqa');

```
