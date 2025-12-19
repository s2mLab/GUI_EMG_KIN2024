NET.addAssembly('MccDaq');

b = MccDaq.MccBoard(0);
chan  = 0;
range = MccDaq.Range.Bip5Volts;

% AIn : récupérer la valeur en sortie (out param)
[err, data] = b.AIn(chan, range);
fprintf('AIn err=%d | raw=%d\n', int32(err.Value), int32(data));

% Conversion en Volts
[err2, volts] = b.ToEngUnits(range, data);
fprintf('ToEngUnits err=%d | volts=%.6f V\n', int32(err2.Value), double(volts));
