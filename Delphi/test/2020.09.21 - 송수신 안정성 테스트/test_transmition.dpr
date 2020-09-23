program test_transmition;

uses
  Vcl.Forms,
  _fmMain in '_fmMain.pas' {Form1},
  Globals in 'Globals.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
