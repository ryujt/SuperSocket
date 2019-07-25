program Example;

uses
  Vcl.Forms,
  _fmMain in '_fmMain.pas' {fmMain},
  TextProtocol in 'TextProtocol.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfmMain, fmMain);
  Application.Run;
end.
