% GEN_TRAIN Simulates a spike train from extracellular recording
%
% Syntax:
%     v = gen_train(templates, Naxons, fs, duration, <options>);
%     [v, vv] = gen_train(templates, Naxons, fs, duration, <options>);
%     v = gen_train(templates, Naxons, fs, duration, 'SpikeRate', sr)
%     v = gen_train(templates, Naxons, fs, duration, 'Overlap', true);
%
% Inputs:
%     templates   -  matrix of spike templates where each column represents
%                    a spike template.
%     Naxons      -  Scalar indicating the number of different axons. Each
%                    axon is assigned a template randomly and a random
%                    average amplitude.
%     fs          -  Sampling rate
%     duration    -  Duration of the simulation in samples.
%
%     <options>
%     'SpikeRate' -  (Optional) Average spike rate of all axons if scalar,
%                    spike rate of each axon if a vector size Naxons x 1.
%                    Default value is 100 spikes per second for all axons.
%     'Overlap'   -  (Optional) If true (default), spikes can occur
%                    simultaneously.
%     'Recruited' -  (Optional) Number  of axons that are recruited along
%                    the recording. All the others start at time = 0.
%                    Default is 0.
%     'Dismissed' -  (Optional) Number of axons that are lost or stop
%                    spiking before the end of the recording. All others
%                    continue until time = end. Default is 0.
%     'Events'    -  (Optional, Struct) Contains fields that reflect in
%                    changes of spike rate or amplitude of some or all
%                    axons
%
% Outputs:
%     v           -  Simulation of an extracellular spiking recording.
%     vv          -  Simulation before adding the axons. Matrix of
%                    dimension Naxons x duration in samples.
%
% Artemio Soto-Breceda | 6/August/2019

%% Copyright 2019 Artemio Soto-Breceda
% 
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
% 
%     http://www.apache.org/licenses/LICENSE-2.0
% 
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.

%%
function [v, vv, report] = gen_train(templates, Naxons, fs, duration, varargin)
   % Default inputs
   opts.SpikeRate = 100;
   opts.Overlap = true;
   opts.Recruited = 0;
   opts.Dismissed = 0;
   
   % Options
	% Validate inputs and assign optional values
   if nargin > 4 && mod(nargin,2)
      fprintf(2,'\tOptions must be pairs of Name(string) and Value\n');
   else
      for i = 1:2:nargin-4
         opts.(varargin{i}) = varargin{i + 1};
      end
   end
   
   % If SpikeRate is scalar, produce a vector of Naxons x 1 with random
   % numbers in the range [0.5*SpikeRate , 1.5*SpikeRate]
   if numel(opts.SpikeRate) == 1
      r = 0.5 + (1.5 - 0.5) .* rand(Naxons,1);
      opts.SpikeRate = r .* opts.SpikeRate;
   end
   
   % Amplitudes of each axon. Amplitude variability sampled from the range
   % [sqrt(2)/2, sqrt(2)]. Range of amplitudes taken from:
   % Rossant et al, 'Spike sorting for large, dense electrode arrays',
   % Nature Neuroscience, 2016 
   % sqrt(2)/2 + (sqrt(2) - sqrt(2)/2)
   r = rand(Naxons,1) .* (1 + poissrnd(1, [Naxons, 1])); % Random from Poisson distribution without 0
   amplitudes = ones(size(opts.SpikeRate));
   amplitudes = r' .* amplitudes;
   amplitudes(amplitudes < 0.5) = 0.5;
   
   % Starting time of each axon
   st_time = ones(size(opts.SpikeRate)); % Sample 1
   axs = randperm(Naxons, opts.Recruited); % Axons to be recruited along the recording
   st_time(axs) = randi(round(2*duration/3), [opts.Recruited, 1]);
   
   % Endinf time of each axon
   end_time = duration * ones(size(opts.SpikeRate)); % Sample 1
   axs = randperm(Naxons, opts.Dismissed); % Axons to be dismissed along the recording
   end_time(axs) = randi(round([(duration/3) ,duration]), [opts.Dismissed, 1]);
      
   % Run the simulation
   [vv, rr] = run_simulation(Naxons, templates, fs, duration ,opts ,amplitudes, st_time, end_time);
   
   % Sum all axons
   v = sum(vv,2);
   
   % Normalize to maximum value
   v = v * max(v);
   
   % Return information about the simulation
   report = struct;
   report.opts = opts;
   report.recruit = st_time;
   report.dismiss = end_time;
   % Copy the report from 'rr' ('run_simulation' function) to 'report'
   for fn = fieldnames(rr)'
      report.(fn{1}) = rr.(fn{1});
   end   
end

% Run the simulation. Returns spike trains per axon in vv.
function [vv, report] = run_simulation(Naxons, templates, fs, duration ,opts ,amplitudes ,st_time , end_time)
   dt = 1/fs;
   T = dt:dt:duration*dt;
   vv = zeros(duration, Naxons);
   spks = zeros(duration, Naxons);
   locs = cell(Naxons, 1);
   max_spike_num = ceil(max(opts.SpikeRate(:)*duration*dt)); % Maximum number of spikes
   
   % Output variable
   report = struct;
   
   % Check for special events
   if isfield(opts,'Events')
      % Inflammation
      if opts.Events.inflammation_axons > 0
         inflamed = randperm(Naxons, opts.Events.inflammation_axons);
         inf_time = opts.Events.inflammation_onset;
         tau = opts.Events.inflammation_tau;
         report.inf_time = inf_time;
         report.inflamed = inflamed;
      else
         inflamed = 0;
         report.inflamed = inflamed;
      end
      
      % Sudden change of amplitude for some axons (natural)
      if opts.Events.amplitude_nat_axons > 0
         amped = randperm(Naxons, opts.Events.amplitude_nat_axons);
         amp_time = opts.Events.amplitude_nat_onset;
         report.amped = amped;
         report.amp_time = amp_time;
      else
         amped = 0;
         report.amped = amped;
      end
      
      % Sudden change of all amplitudes (disturbance)
      amp_disturbance_onset = opts.Events.amplitude_dist_onset;
      amp_disturbance_value = opts.Events.amplitude_dist_value;
      amp_disturbance_probability = opts.Events.amplitude_dist_prob;
   end
   
   if opts.RepeatTemplates
      % Random list of templates (can repeat)
      templates_ = randi(size(templates,2), 1, Naxons);
   else
      % Random list of templates (non repeating)
      templates_ = randperm(size(templates,2), Naxons);
   end
   % Progress bar
   w = waitbar(0, 'Generating simulation...');
   for i = 1:Naxons
      % Check that start time is smaller than end time
      if end_time(i) < st_time(i)
         % if end is smaller, invert the values
         et = end_time(i);
         end_time(i) = st_time(i);
         st_time(i) = et;
      end
      
      currentTemplate = templates_(i); % Randomly pick 1 of the templates to assign to this axon.
      isi = random('Exponential', fs/opts.SpikeRate(i), [3 * max_spike_num 1]);
      isi = round(isi);
      % Remove isi that are closer than the duration of a spike
      isi(isi < size(templates,1)) = size(templates,1);
      
      % If it doesn't get affected by inflammation, it's firing rate
      % remains constant. If it does, we will remove the isi's who's cumsum
      % go beyond the inflamation time.
      % Check if this axon gets an inflammation event
      if ~isempty(find(inflamed == i,1))
         % If it gets inflamed, change the firing rate at 
         % time = evnts.inflammation_onset
         inf_sample = find(cumsum(isi) > inf_time, 1, 'first');
         sr = 9 * exp(-(1:numel(isi)-inf_sample)/(tau)) + 1; % Get an exponential from 10 to 1 with time constant tau
         isi(inf_sample + 1:end) = isi(inf_sample + 1:end)./sr';
         % Remove isi that are closer than the duration of a spike
         isi(isi < size(templates,1)) = size(templates,1);
         isi = ceil(isi);
      end
        
      % Get spike times
      sptimes = cumsum(isi);
            
      % Remove spikes that exceed the duration of the recording or the end
      % time of the particular axon
      sptimes(sptimes > end_time(i)) = [];
      % Remove spikes that occur befor the axon is recruited
      sptimes(sptimes < st_time(i)) = [];
      
      % Check for overlapping spikes on different recordings. If overlap is
      % false, then don't allow overlapping.
      if ~opts.Overlap
      % Only if opts.overlap is false
         if i > 1
            for ii = 1:length(allsptimes)
               % Remove the opts.overlapped
               sptimes(((sptimes >= allsptimes(ii) - size(templates,1))...
                  & (sptimes < allsptimes(ii) + size(templates,1)))) = [];
               % Update progress
               try w = waitbar((i-1)/Naxons + ii/(length(allsptimes)*Naxons), w); catch E, delete(w); error('Manually stopped'); end
            end
         else
            allsptimes = [];
         end
         allsptimes = [allsptimes; sptimes];
      end
      
      % Create a recording of zeroes
      v_ = zeros(duration, 1);
      spks(:,i) = zeros(duration, 1);
      
      % Assign binary spikes to the vector, the amplitude of the spikes is
      % weighted, instead of being just 1 or 0.
      v_(sptimes) = amplitudes(i);
      spks(sptimes,i) = 1;
      % Vary the amplitude
      rand_amp = 0.99 + (1.01 - 0.99) .* rand(size(sptimes)); % small variation in amplitude
      v_(sptimes) = v_(sptimes).*rand_amp;
      
      % If the amplitude of current axon changes suddenly, scale all the
      % spikes after such time.
      % Ref: quirk2001, tsubokawa1996
      if ~isempty(find(amped == i,1))
         end_amp = (0.5 * rand(1,1) - 0.25); % Change in amplitude limited to 0.15 and -0.15
         log_amp = amplitudes(i) + (end_amp./(1 + exp(-10 * dt * ([1 : length(v_)] - amp_time)))); % logistic function
         v_ = v_ .* log_amp';
      end
      
      % Propagate the spike shape along the spikes vector
      v_ = conv(v_,templates(:,currentTemplate), 'same');
      
      % Assign the temporal variable v_ to the matrix of axons
      vv(:,i) = v_;
      
      % Save the sike locations (times) in report.locs
      locs{i} = sptimes;
      
      % Update progress
      try w = waitbar(i/Naxons, w); catch, delete(w); error('Manually stopped'); end
   end
   
   % If the amplitude of all spikes change due to a disturbance, simply
   % multiply all the values of v_ after the change in time.
   if (amp_disturbance_onset > 0) && (rand < amp_disturbance_probability)
      vv(amp_disturbance_onset : end, : ) = vv(amp_disturbance_onset : end, : ) * amp_disturbance_value;
   end
   
   report.locs = locs;
   report.spks = spks;
   
   % Close progress bar
   try delete(w); catch E, fprintf(2,'\t%s\n',E.message); end
end