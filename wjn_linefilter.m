function D=wjn_linefilter(filename,lhz)

if ~exist('lhz','var')
    lhz = 50;
end

D=spm_eeg_load(filename);

chans = 1:D.nchannels;

iother = D.indchantype('Other');
chans(iother)=[];

franges = [lhz:lhz:D.fsample/2];


cfg = [];
cfg.dftfilter = 'yes';
cfg.dftfreq = franges;
cfg.channel = chans;
data = ft_preprocessing(cfg,D.ftraw(0));

for a = 1:length(data.trial)
    d(chans,:,a) = data.trial{a};
end

D=D.copy(fullfile(D.path,['lf' D.fname]));
D(chans,:,:)=d;
save(D);

