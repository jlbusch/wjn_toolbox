function D=wjn_notchfilter(filename)
D=spm_eeg_load(filename);
data = spm2fieldtrip(D);
conds = D.conditions;
fs = D.fsample;
cfg = [];
cfg.bsfilter = 'yes';
lf = [45:50:.5*fs-5];
cfg.bsfreq = [lf' lf'+10];
data = ft_preprocessing(cfg,data);
D=spm_eeg_ft2spm(data,['f' D.fname]);