program P2P_Server;

uses
  Vcl.Forms,
  _fmMain in '_fmMain.pas' {fmMain},
  Database in 'Database.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfmMain, fmMain);
  Application.Run;
end.
