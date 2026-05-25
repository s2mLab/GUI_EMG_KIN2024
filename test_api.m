load_mccdaq_assembly();

b = MccDaq.MccBoard(0);
chan  = 0;
range = MccDaq.Range.Bip5Volts;

% AIn : récupérer la valeur en sortie (out param)
[err, data] = b.AIn(chan, range);
fprintf('AIn err=%d | raw=%d\n', int32(err.Value), int32(data));
if int32(err.Value) ~= 0
    fprintf('Message MCC : %s\n', char(err.Message));
    if int32(err.Value) == 126
        error(['CB.CFG introuvable. Ouvrez InstaCal, ajoutez la carte MCC ' ...
            'et assignez-la au numero 0 avant de relancer ce test.']);
    end
    error('Echec AIn MCC : %s', char(err.Message));
end

% Conversion en Volts
[err2, volts] = b.ToEngUnits(range, data);
fprintf('ToEngUnits err=%d | volts=%.6f V\n', int32(err2.Value), double(volts));
