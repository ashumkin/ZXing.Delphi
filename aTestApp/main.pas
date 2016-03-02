unit main;
{
  * Copyright 2015 E Spelt for test project stuff
  *
  * Licensed under the Apache License, Version 2.0 (the "License");
  * you may not use this file except in compliance with the License.
  * You may obtain a copy of the License at
  *
  *      http://www.apache.org/licenses/LICENSE-2.0
  *
  * Unless required by applicable law or agreed to in writing, software
  * distributed under the License is distributed on an "AS IS" BASIS,
  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  * See the License for the specific language governing permissions and
  * limitations under the License.

  * Implemented by E. Spelt for Delphi
}
interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Objects,
  FMX.StdCtrls, FMX.Media, FMX.Platform, FMX.MultiView, FMX.ListView.Types,
  FMX.ListView, FMX.Layouts, System.Actions, FMX.ActnList, FMX.TabControl,
  FMX.ListBox, Threading, BarcodeFormat, ReadResult,
  FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo, ScanManager;

type
  TMainForm = class(TForm)
    btnStartCamera: TButton;
    btnStopCamera: TButton;
    lblScanStatus: TLabel;
    imgCamera: TImage;
    ToolBar1: TToolBar;
    btnMenu: TButton;
    Layout2: TLayout;
    ToolBar3: TToolBar;
    CameraComponent1: TCameraComponent;
    Memo1: TMemo;
    imgCameraLaser: TImage;
    lay1: TLayout;
    procedure btnStartCameraClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnStopCameraClick(Sender: TObject);

    procedure FormDestroy(Sender: TObject);
    procedure CameraComponent1SampleBufferReady(Sender: TObject;
      const ATime: TMediaTime);
  private
    const cLaserWidth = 16;
    var
    { Private declarations }

    FScanManager: TScanManager;
    FScanInProgress: Boolean;
    frameTake: Integer;
    FScanBitmap: TBitmap;
    FLaserScanBitmap: TBitmap;
    procedure GetImage();
    function AppEvent(AAppEvent: TApplicationEvent; AContext: TObject): Boolean;

  public
    { Public declarations }
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.fmx}

procedure TMainForm.FormCreate(Sender: TObject);
var
  AppEventSvc: IFMXApplicationEventService;
begin

  lblScanStatus.Text := '';
  frameTake := 0;

  { by default, we start with Front Camera and Flash Off }
  { cbFrontCamera.IsChecked := True;
    CameraComponent1.Kind := FMX.Media.TCameraKind.ckFrontCamera;

    cbFlashOff.IsChecked := True;
    if CameraComponent1.HasFlash then
    CameraComponent1.FlashMode := FMX.Media.TFlashMode.fmFlashOff;
  }

  { Add platform service to see camera state. }
  if TPlatformServices.Current.SupportsPlatformService
    (IFMXApplicationEventService, IInterface(AppEventSvc)) then
    AppEventSvc.SetApplicationEventHandler(AppEvent);

  CameraComponent1.Quality := FMX.Media.TVideoCaptureQuality.MediumQuality;
  lblScanStatus.Text := '';
  FScanManager := TScanManager.Create(TBarcodeFormat.Auto, nil);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  FScanManager.Free;
end;

procedure TMainForm.btnStartCameraClick(Sender: TObject);
begin
  CameraComponent1.Active := False;
  CameraComponent1.Kind := FMX.Media.TCameraKind.BackCamera;
  CameraComponent1.Active := True;

  lblScanStatus.Text := '';
  memo1.Lines.Clear;

end;

procedure TMainForm.btnStopCameraClick(Sender: TObject);
begin
  CameraComponent1.Active := False;
end;

procedure TMainForm.CameraComponent1SampleBufferReady(Sender: TObject;
  const ATime: TMediaTime);
begin
  TThread.Synchronize(TThread.CurrentThread, GetImage);
end;

procedure TMainForm.GetImage;
var
  ReadResult: TReadResult;
  LBeginTime: Cardinal;
  LSrcRect, LDestRect: TRectF;
begin
  CameraComponent1.SampleBufferToBitmap(FScanBitmap, True);
  // draw image
  imgCamera.Bitmap.Assign(FScanBitmap);
  // init bitmap of imgCameraLaser
  imgCameraLaser.Bitmap.Assign(imgCamera.Bitmap);

  {
    inc(frameTake);
    if (frameTake mod 4 <> 0) then
    begin
    Exit;
    end;
  }

  // calc "laser area"
  LSrcRect.Create(0, 0, FScanBitmap.Width, FScanBitmap.Height);
  LDestRect := LSrcRect;
  OffsetRect(LSrcRect, 0, (LSrcRect.Height - cLaserWidth) / 2);
  try
    LSrcRect.Height := cLaserWidth;
    LDestRect.Height := LSrcRect.Height;
    // get "laser area"
    if imgCameraLaser.Bitmap.Canvas.BeginScene then
      try
        imgCameraLaser.Bitmap.Canvas.DrawBitmap(imgCamera.Bitmap, LSrcRect, LDestRect, 1, True);
      finally
        imgCameraLaser.Bitmap.Canvas.EndScene;
      end;
    // draw "laser"
    if imgCamera.Bitmap.Canvas.BeginScene then
      try
        imgCamera.Bitmap.Canvas.Stroke.Thickness := 3;
        imgCamera.Bitmap.Canvas.Stroke.Color := TAlphaColorRec.Red;
        imgCamera.Bitmap.Canvas.DrawRect(LSrcRect, 0, 0, AllCorners, 1);
      finally
        imgCamera.Bitmap.Canvas.EndScene;
      end;
  except
    on E: Exception do
    begin
      Log.d('Exception: %s: %s', [E.ClassName, E.Message]);
      Exit;
    end;
  end;

  if (FScanInProgress) then
  begin
    Exit;
  end;

  TTask.Run(
    procedure
    begin

      try
        FScanInProgress := True;

        FLaserScanBitmap.Assign(imgCameraLaser.Bitmap);
        // scan laser first
        {$IFDEF DEBUG}
        LBeginTime := TThread.GetTickCount;
        {$ENDIF}
        ReadResult := FScanManager.Scan(FLaserScanBitmap);
        {$IFDEF DEBUG}
        Log.d('Laser scan completed in %d ticks', [TThread.GetTickCount - LBeginTime]);
        {$ENDIF}
        if not Assigned(ReadResult) then
        begin
          {$IFDEF DEBUG}
          LBeginTime := TThread.GetTickCount;
          {$ENDIF}
          ReadResult := FScanManager.Scan(FScanBitmap);
          {$IFDEF DEBUG}
          Log.d('Scan completed in %d ticks', [TThread.GetTickCount - LBeginTime]);
          {$ENDIF}
        end;
        FScanInProgress := False;
      except
        on E: Exception do
        begin
          FScanInProgress := False;
          TThread.Synchronize(nil,
            procedure
            begin
              // lblScanStatus.Text := E.Message;
              // lblScanResults.Text := '';
            end);

          Exit;

        end;

      end;

      TThread.Synchronize(nil,
        procedure
        begin

          if (length(lblScanStatus.Text) > 10) then
          begin
            lblScanStatus.Text := '*';
          end;

          lblScanStatus.Text := lblScanStatus.Text + '*';

          if (ReadResult <> nil) then
          begin
            memo1.Lines.Insert(0, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz: ', Now) + ReadResult.Text);
          end;

          FreeAndNil(ReadResult);

        end);
    end);

end;

procedure TMainForm.AfterConstruction;
begin
  inherited;
  FScanBitmap := TBitmap.Create;
  FLaserScanBitmap := TBitmap.Create;
end;

function TMainForm.AppEvent(AAppEvent: TApplicationEvent;
AContext: TObject): Boolean;
begin
{ Make sure the camera is released if you're going away. }
  case AAppEvent of
    TApplicationEvent.WillBecomeInactive:
      CameraComponent1.Active := False;
    TApplicationEvent.EnteredBackground:
      CameraComponent1.Active := False;
    TApplicationEvent.WillTerminate:
      CameraComponent1.Active := False;
  end;

end;

procedure TMainForm.BeforeDestruction;
begin
  FScanBitmap.DisposeOf;
  FLaserScanBitmap.DisposeOf;
  inherited;
end;

end.
