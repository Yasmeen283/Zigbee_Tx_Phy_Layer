function [binary] = decimal2binary(decimal,bitsnumber,decimal_length) 
% ----------------------------------------------------------------------- %
% ----------------------------------------------------------------------- %
% Algorithm to convert from decimal to binary 
% binary = zeros(decimal_length,bitsnumber);
% 
%     for i = 1 : bitsnumber
%        binary (:,bitsnumber +1 -i) = mod (decimal(1:decimal_length),2);
%        decimal(1:decimal_length) =  floor(decimal(1:decimal_length)/2);
%     end
% ----------------------------------------------------------------------- %
% avoid using for loop 
% use dec2bin to convert from decimal to string 
% use str2num to convert the string output from the dec2bin to digits 
binary = str2num ( reshape  ...
        (dec2bin(decimal,bitsnumber)',decimal_length*bitsnumber,1));

end
 