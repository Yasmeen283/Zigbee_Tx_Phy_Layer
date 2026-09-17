% =========================================================================
% IEEE 802.15.4 CSS PHY - Test Vector Generator for RTL Verification
% Saves payload inputs and golden MATLAB outputs to test_vectors/
% =========================================================================
clear; clc; close all;

addpath('common'); addpath('transmitter');

global chirpIndex;
chirpIndex = 1;

out_dir = 'test_vectors';
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

globalSettings();

global samplingFreqMhz;
global TxDACbitNumber;


chirpSeq = chirpSequenceGenerator(chirpIndex, samplingFreqMhz);

chirpRomBitNumber = 5;   % must match ROM_WIDTH_CFG in tb.sv / css_tx_top
chirpSeq_Tx = floor(chirpSeq * (2^(chirpRomBitNumber - 1) - 1));
%chirpSeq_Tx = floor(chirpSeq * (2^(TxDACbitNumber - 1) - 1));

rates = [0, 1];            % 0 = 1 Mbps, 1 = 250 kbps
lengths = [0, 1, 50, 127]; % Target payload lengths

for r = rates
    rate_str = ternary(r == 0, '1Mbps', '250kbps');
    fprintf('====================================================\n');
    fprintf(' Generating Reference Vectors: %s\n', rate_str);
    fprintf('====================================================\n');
    
    for L = lengths
        % --- Generate Payload Bytes ---
        if L == 0
            payload_bytes = uint8([]);
            incomingStream = [];
        else
            payload_bytes = uint8(mod(0:L-1, 256));
            bits_mat = zeros(L, 8);
            for b = 1:8
                bits_mat(:, b) = bitget(payload_bytes(:), b);
            end
            incomingStream = reshape(bits_mat', 1, []);
        end
        
        % --- Save Payload File for RTL Testbench Input ---
        payload_file = sprintf('%s/payload_len%03d.txt', out_dir, L);
        fid = fopen(payload_file, 'wt');
        if ~isempty(payload_bytes)
            fprintf(fid, '%02X\n', payload_bytes);
        end
        fclose(fid);
        
        % --- Run Reference TX Processing Chain ---
        TxOutput = ChirpSpreadSpectrum_Tx(incomingStream, r, chirpSeq_Tx);
        
        Tx_real = real(TxOutput);
        Tx_imag = imag(TxOutput);
        
        % --- Export Golden Stage 13 Fixed-Point Outputs ---
        real_file = sprintf('%s/mat_%s_len%03d_real.txt', out_dir, rate_str, L);
        imag_file = sprintf('%s/mat_%s_len%03d_imag.txt', out_dir, rate_str, L);
        
        fid_r = fopen(real_file, 'wt');
        fprintf(fid_r, '%d\n', Tx_real);
        fclose(fid_r);
        
        fid_i = fopen(imag_file, 'wt');
        fprintf(fid_i, '%d\n', Tx_imag);
        fclose(fid_i);
        
        fprintf('  [OK] L = %3d | Total Samples: %d\n', L, length(TxOutput));
    end
end

fprintf('\nAll test vectors generated successfully in "%s/".\n', out_dir);

function val = ternary(cond, val_true, val_false)
    if cond, val = val_true; else, val = val_false; end
end