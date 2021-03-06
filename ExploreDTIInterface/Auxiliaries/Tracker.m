%%%$ Included in MRIToolkit (https://github.com/delucaal/MRIToolkit) %%%%%% Alberto De Luca - alberto@isi.uu.nl $%%%%%% Distributed under the terms of LGPLv3  %%%



classdef Tracker < handle
% Originally written from Ben Jeurissen (ben.jeurissen@uantwerpen.be)
% under the supervision of Alexander Leemans (a.leemans@umcutrecht.nl)
%
    % Abstract Tractography class
    %
    % see also DTITracker, FODTracker
    %
    % Copyright Ben Jeurissen (ben.jeurissen@ua.ac.be)
    %
    properties (Access = protected)
        f;
        v2w;
        stepSize;
        threshold;
        maxAngle;
        lengthRange;
        fun;
        iterations = 1;
        pb = false;
    end
    
    methods (Access = public)
        function this = Tracker(v2w)
            this.v2w = single(v2w);
        end
        
        function this = setData(this, f)
            this.f = single(f);
        end
        
        function this = setParameters(this, stepSize, threshold, maxAngle, lengthRange)
            if stepSize > 0
                this.stepSize = single(stepSize);
            else
                error('stepSize must be > 0');
            end
            if threshold >= 0
                this.threshold = single(threshold);
            else
                error('threshold must be >= 0');
            end
            if maxAngle > 0 && maxAngle <= 90
                this.maxAngle = single(maxAngle);
            else
                error('maxAngle must be in [0 90]');
            end
            if lengthRange(1) >= stepSize
                if (lengthRange(1) <= lengthRange(2))
                    this.lengthRange = single(lengthRange);
                else
                    error('lengthRange(2) must be >= lengthRange(1)');
                end
            else
                error('lengthRange(1) must be >= stepSize');
            end
        end
        
        function this = setProgressbar(this, val)
            this.pb = val;
        end
        
        function [tract, tractVal] = track(this, point)
            point = single(point);
            if (isempty(this.stepSize) || isempty(this.threshold) || isempty(this.maxAngle) || isempty (this.lengthRange))
                error('set tracking parameters first, using setParameters');
            end
            if isempty(this.f)
                error('set input data first, using setData');
            end
            
            % interpolate
            this.interpolate(point);
            
            % mask out NaN values
            mask = ~isnan(this.fun(1,:));
            point = point(:,mask);
            this.fun = this.fun(:,mask);
            
            % process function
            this.process();
            
            % determine initial track direction(s)
            [point, dir, val] = this.getInitDir(point);
            
            % mask out all small peaks
            mask = val > this.threshold;
            point = point(:,mask);
            dir = dir(:,mask);
            
            % repeat data for probabilistic tractography
            point = repmat(point,[1 this.iterations]);
            dir = repmat(dir,[1 this.iterations]);
            val = repmat(val,[1 this.iterations]);
            
            % Track in both directions
            if this.pb; progressbar('start', [size(point,2) 1], 'Tracking in first direction'); end;
            [tract1, tractVal1] = this.trackOneDir(point, dir);
            if this.pb; progressbar('ready'); end;
            
            if this.pb; progressbar('start', [size(point,2) 1], 'Tracking in second direction'); end;
            [tract2, tractVal2] = this.trackOneDir(point, -dir);
            if this.pb; progressbar('ready'); end;
            
            % join tracts from both directions
            tract2 = cellfun(@flipud,tract2,'UniformOutput',false);
            tractVal2 = cellfun(@flipud,tractVal2,'UniformOutput',false);
            tract = cell(size(tract2));
            tractVal = cell(size(tractVal2));
            for j = 1:size(tract2,2)
                if ~isempty(tract2{j})
                    tract{j} = [tract2{j}; point(:,j)'];
                    tractVal{j} = [tractVal2{j}; val(:,j)'];
                    if ~isempty(tract1{j})
                        tract{j} = [tract{j}; tract1{j}];
                        tractVal{j} = [tractVal{j}; tractVal1{j}];
                    end
                else
                    if ~isempty(tract1{j})
                        tract{j} = [point(:,j)'; tract1{j}];
                        tractVal{j} = [val(:,j)'; tractVal1{j}];
                    end
                end
            end
            
            % enforce length limitations
            %             maska = cellfun('size',tract,1)*this.stepSize >= this.lengthRange(1);
            %             maskb = cellfun('size',tract,1)*this.stepSize <= this.lengthRange(2);
            %             mask = maska & maskb;
            %             tract = tract(mask);
            %             tractVal = tractVal(mask);
            mask = cellfun('size',tract,1)>1;
            tract = tract(mask);
            tractVal = tractVal(mask);
        end
    end
    
    methods (Access = private)
        function [tract, tractVal] = trackOneDir(this, point, dir)
            tract = cell(1,size(point,2));
            tractVal = cell(1,size(point,2));
            flist = 1:size(point,2);
            
            for it = 1:(this.lengthRange(2)/this.stepSize)
                if this.pb; progressbar(size(point,2),int2str(size(point,2))); end;
                % advance streamline
                try

                    point = point + this.stepSize .* dir;
                catch
                    disp('Size point:')
                    disp(num2str(size(point)))
                    disp('Size step:')
                    disp(num2str(size(this.stepSize)))
                    disp('Size dir:')
                    disp(num2str(size(dir)))
                    continue
%                     error('The error...')
                end
                
                % interpolate
                this.interpolate(point);
                
                % mask out NaN values
                mask = ~isnan(this.fun(1,:));
                point = point(:,mask);
                dir = dir(:,mask);
                this.fun = this.fun(:,mask);
                flist = flist(mask);
                
                % process function
                this.process();
                
                % get new direction
                [newDir, val, angle] = this.getDir(dir);
                
                % mask out small peaks
                mask = val > this.threshold;
                point = point(:,mask);
                dir = dir(:,mask);
                newDir = newDir(:,mask);
                flist = flist(mask);
                angle = angle(mask);
                val = val(:,mask);
                
                % mask out large angles
                mask = angle < this.maxAngle;
                point = point(:,mask);
                dir = dir(:,mask);
                newDir = newDir(:,mask);
                flist = flist(mask);
                val = val(:,mask);
                
                % make sure we don't move back in the streamline
                flipsign = sign(sum(dir.*newDir,1));
                
                % update dir
                dir = flipsign([1 1 1],:).*newDir;
                
                % stop if we are out of points
                if isempty(point)
                    break
                end
                
                % add points to the tracts
                for i=1:length(flist)
                    tract{flist(i)}(it,:) = point(:,i);
                    tractVal{flist(i)}(it,:) = val(:,i);
                end
            end
        end
        
        function interpolate(this, point)
            point(4,:) = 1; voxel = this.v2w\point; voxel = voxel(1:3,:);
            this.fun = mex_interp(this.f, voxel);
        end
    end
    methods (Access = protected, Abstract = true)
        process(this);
        [point, dir, val] = getInitDir(this, point);
        [dir, val, angle] = getDir(this, prevDir);
    end
end