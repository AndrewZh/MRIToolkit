%%%$ Included in MRIToolkit (https://github.com/delucaal/MRIToolkit) %%%



% Originally written from Ben Jeurissen (ben.jeurissen@uantwerpen.be)
% under the supervision of Alexander Leemans (a.leemans@umcutrecht.nl)
function y = unlinearize4d_cell(x,mask)
dims = size(mask);

for k = 1:size(x,1)
    
    y{k} = repmat(single(nan),[dims(1) dims(2) dims(3)]);
    y{k}(mask)=x(k,:);
    
end
   