@ECHO off
setlocal enabledelayedexpansion

set currentVersion=1.5

set manualModification=disabled
set keepFiles=false
set pickDestinationFolder=false
set silent=false

set dreamOnBootMenu=DreamOn2
set dp3BootMenu=DP3

set bootMenu=!dreamOnBootMenu!


set gameFolderPostfix=GameFolderDreamcast
set gameWorkingDir=%~dp0%gameFolderPostfix%


::read input params
:loop_param_main
IF NOT "%1"=="" (
	
    IF "%1"=="-modify" (
        SET manualModification=enabled
    )
	IF "%1"=="-keep" (
        SET keepFiles=true
    )
	IF "%1"=="-silent" (
        SET silent=true
    )
	if "%1"=="-dest" ( 
		set pickDestinationFolder=true
	    call :pick_dialog -folder -title "Pick output folder"
		if defined fileNameList set gameWorkingDir=!fileNameList!\%gameFolderPostfix%
    )

	if "%1"=="-dp3" ( 
		set bootMenu=!dp3BootMenu!
    )
	
    SHIFT
    GOTO :loop_param_main 
)

echo version %currentVersion%
echo.
echo Tool for preparing CDI images for burning to CD-R. Allows easy creation of multi game compilation images based on DreamOn menu by default or using DP3 browser as an option.
echo.
echo gameWorkingDir=!gameWorkingDir!
echo.
echo -modify=%manualModification% (allows modification of extracted folder before creating final CDI image)
echo -keep=%keepFiles% (flag for preserving all intermediate files)
echo -silent=%silent% (multi game disc only. flag for skipping custom display name for games and image cobver dialog)
echo -dest=%pickDestinationFolder% (choose destination folder for extracting and creating final CDI image)

echo boot menu=!bootMenu! (Use -dp3 flag to use DP3 boot menu (may work with some games while DreamOn fails))


call :pick_dialog -multiselect -filter "CDI Files (*.cdi)|*.cdi|All Files (*.*)|*.*" -title "Open game images (Ctrl/Shift for multiple selection)" 

if not defined fileNameList (
	echo No file was choosen. Exiting...
	pause
	goto :EOF
)

set /a fileCount=0
for %%i in ("%fileNameList:;=","%") do set /a "fileCount+=1"



if %filecount%==1 (
	for %%i in ("%fileNameList:;=","%") do ( set filePath=%%~i 
		call :cdi_to_data_data_folder "!filePath!"
		if "!initialFileFormat!"=="Data-Data" ( pause & goto :EOF )

	)
) else ( 
	::extract boot menu
	7z x -y !bootMenu!.zip >nul
	call :multiple_cdi_to_data_data_folder "!fileNameList!"
	::clean up boot menu folder
	if exist !bootMenu!.zip call :delete_folder !bootMenu!
)

	
call :bootable_cdi_from_folder


pause
goto :EOF


 

:pick_dialog
:: launches a File... Open sort of file chooser and outputs choice to the console

@echo off

::read input params
set isMultiselect=false
set "fileNameList="
set defaultTitle="Open a file"
set "defaultFilter=All Files (*.*)|*.*"
set dialogType=file


:loop_param_pick_dialog
IF NOT "%1"=="" (
	
    IF "%1"=="-filter" (
        set "filter=%~2"
		SHIFT
    )
	IF "%1"=="-title" (
        set title=%2
		SHIFT
    )
	IF "%1"=="-multiselect" (
		if %dialogType%==file set isMultiselect=true
    )
	
	IF "%1"=="-folder" (
        set dialogType=folder
		set isMultiselect=false
		set defaultTitle="Pick a folder"
    )
    SHIFT
    GOTO :loop_param_pick_dialog 
)
	
if "filter"=="" set "filter=%defaultFilter%"
if "%title:"=%"=="" set title=%defaultTitle% 
 
:: Does powershell.exe exist within %PATH%?

::for %%I in (`powershell.exe`) do if "%%~$PATH:I" neq "" (
::    set chooser=powershell "Add-Type -AssemblyName System.windows.forms|Out-Null;$f=New-Object ::System.Windows.Forms.OpenFileDialog;$f.InitialDirectory='%cd%';$f.Filter='%filter%';$f.showHelp=$true;$f.ShowDialog()|Out-Null;$f.FileName"
::) else 
(
rem :: If not, compose and link C# application to open file browser dialog

    set chooser=%temp%\chooser.exe
	if %dialogType%==folder ( 
	
	>"%temp%\c.cs" echo using System;using System.Windows.Forms;
    >>"%temp%\c.cs" echo class dummy{[STAThread]
    >>"%temp%\c.cs" echo public static void Main^(^){
    >>"%temp%\c.cs" echo FolderBrowserDialog f=new FolderBrowserDialog^(^);
    >>"%temp%\c.cs" echo f.SelectedPath=System.Environment.CurrentDirectory;
    >>"%temp%\c.cs" echo f.Description=!title!;
    >>"%temp%\c.cs" echo f.ShowNewFolderButton=true;
    >>"%temp%\c.cs" echo f.ShowDialog^(^);
	>>"%temp%\c.cs" echo Console.Write^(f.SelectedPath^);}}
   	
	 ) else ( 
    >"%temp%\c.cs" echo using System;using System.Windows.Forms;
    >>"%temp%\c.cs" echo class dummy{
    >>"%temp%\c.cs" echo public static void Main^(^){
    >>"%temp%\c.cs" echo OpenFileDialog f=new OpenFileDialog^(^);
    >>"%temp%\c.cs" echo f.InitialDirectory=Environment.CurrentDirectory;
    >>"%temp%\c.cs" echo f.Filter="!filter!";
    >>"%temp%\c.cs" echo f.Title=!title!;
    >>"%temp%\c.cs" echo f.ShowHelp=true;
    >>"%temp%\c.cs" echo f.Multiselect=%isMultiselect%;
	>>"%temp%\c.cs" echo f.ShowDialog^(^);
    >>"%temp%\c.cs" echo int i = 0;foreach(String fileName in f.FileNames^){
    >>"%temp%\c.cs" echo if(i^>0^){Console.Write^(";"^);};Console.Write^(fileName^);i++;}}}
	
	 )

	if exist %chooser% del "!chooser!"
    for /f "delims=" %%I in ('dir /b /s "%windir%\microsoft.net\*csc.exe"') do (
        if not exist "!chooser!" "%%I" /nologo /out:"!chooser!" "%temp%\c.cs" 2>NUL
    )
    ::del "%temp%\c.cs"
    if not exist "!chooser!" (
        echo Error: Please install .NET 2.0 or newer, or install PowerShell.
		pause
        goto :EOF
    )
)


:: capture choice to a variable

for /f "delims=" %%I in ('%chooser%') do set fileNameList=%%I
del %chooser%

echo Choosen fileNameList=%fileNameList%


:: Clean up the mess
del "%temp%\chooser.exe" 2>NUL

exit /b

:multiple_cdi_to_data_data_folder
set filenameList=%1

for /f "tokens=1-2 delims=/:" %%a in ("%TIME%") do (set currentTime=%%a%%b)


		set /a index=0;

		set compilationFolder=CompilationDisc
		set "gameWorkingDir=%gameWorkingDir%\%compilationFolder%"
		set workDirMulti="%gameWorkingDir%\%compilationFolder%"
		call :delete_folder '%workDirMulti%'
		
		echo Unzipping !bootMenu!.zip
::		7z x -y -o!workDirMulti! !bootMenu!.zip >nul
		xcopy /e /s /y /i !bootMenu! %workDirMulti%
		::call :delete_folder '!bootMenu!'
		set "multiGameFileName="
		set "parseGameNameResult="
		::if !bootMenu!==!dreamOnBootMenu! set parseGameNameResult=DreamOn_
		if !bootMenu!==!dp3BootMenu! set parseGameNameResult=DP3_
		for %%i in (%filenamelist:;=","%) do (
		set filePath=%%i
			call :cdi_to_data_data_folder !filePath!
			if "!initialFileFormat!"=="Data-Data" (
				echo Game is in Data-Data format. Only images in Audio-Data format suitable for compilation multi game disc. Skipping !extractedFolder! game...
				set /p WAIT=Press ENTER to continue...
			 ) else ( 
				set gameFolder=!gameFolder:"=!
				echo gameFolder=!gameFolder!
				set /a index+=1
				::DP3 can read folder with maximum up to 11 symbols. 
				::Index as prefex will ensure all games have unique name. 
				set gameFolderDst=!index!_!extractedFolder:~0,8!
				set gameFolderDst=!gameFolderDst:-=_!
				set srcOrigin="!gameFolder!\!extractedFolder!"
				set src="!gameFolder!\!gameFolderDst!"
				set dst=!workDirMulti!
				echo srcOrigin=!srcOrigin!
				echo src=!src!
				echo dst=!dst!
				echo gameFolder=!gameFolder!
				ren !srcOrigin! !gameFolderDst!
				move !src! !dst!
				call :delete_folder '"!gameFolder!"' >nul
			
				::prepare display name
				set displayGameName=""
				if %silent%==false set /p displayGameName=Enter display name for !gameName! ^(leave blank for default value^): 
				if !displayGameName!=="" set displayGameName=!gameName!
				echo Display name=!displayGameName!
				
				::prepare cover image
				set gameImageNameSrc=!displayGameName!
				echo gameImageNameSrc=!gameImageNameSrc!
				set gameImageDst=!index!
				set gameImageFile=!index!.pvr
				set gameImageName=""
				echo Default cover image path = .\!gameImageNameSrc!.jpg
				if exist !gameImageNameSrc!.jpg (
					set gameImageName="!gameImageNameSrc!.jpg"
				)
				if exist "!gameImageNameSrc!.png" ( 
					set gameImageName="!gameImageNameSrc!.png"
				)
				if exist "!gameImageNameSrc!.gif" ( 
					set gameImageName="!gameImageNameSrc!.gif" 
				)
				if %silent%==false ( 
				if not exist !gameImageName! ( 
					echo picking image 
					set "imageFilter=Image (*.jpg, *.jpeg, *.png, *.gif)|*.jpg;*.jpeg;*.png;*.gif|All Files (*.*)|*.*"
					call :pick_dialog -filter "!imageFilter!" -title "Pick cover image for '!displayGameName:_= !'"
					if defined fileNameList set gameImageName="!fileNameList!"
				 )
				 )
				echo gameImageName=!gameImageName!
				
				call :parse_game_name "!displayGameName!"
				
				if !bootMenu!==!dreamOnBootMenu! ( 
					set gameImageDst=!gameImageDst!.bmp
					if exist !gameImageName! ( 
						convert !gameImageName! -resize 256x256 -gravity center -extent 256x256 BMP3:!workDirMulti!/!gameImageDst!
					 ) else ( 
						copy !workDirMulti!\game_logo.bmp !workDirMulti!\!gameImageDst!
						echo No cover image found. Use default image
					 )
					 ::convert bmp image into pvr
					set /a globalIndexPvr=42+!index!
					pvrconv -gi !globalIndexPvr! !workDirMulti!\!gameImageDst!
					del !workDirMulti!\!gameImageDst!
					 
					 
					set gameConfigFile=!gameFolderDst!.cfg
					 
					echo "!displayGameName:_= !" : GAME,"!gameConfigFile!","!gameImageFile!",AUTO>>!workDirMulti!/MENU.cfg

					echo LAUNCH > !workDirMulti!/!gameConfigFile!
					echo PATH "!gameFolderDst!" >> !workDirMulti!/!gameConfigFile!
					echo EXEC "\!gameFolderDst!\!bootFile!" >> !workDirMulti!/!gameConfigFile!
					echo GDDA 7 >> !workDirMulti!/!gameConfigFile!
					echo LAUNCH_END >> !workDirMulti!/!gameConfigFile!
					echo.>> !workDirMulti!/!gameConfigFile!
					echo PRODUCT_INFO ENG>> !workDirMulti!/!gameConfigFile!
					echo "!displayGameName:_= !">> !workDirMulti!/!gameConfigFile!
					echo END_PRODUCT_INFO>> !workDirMulti!/!gameConfigFile!
					echo.>> !workDirMulti!/!gameConfigFile!
					echo CONTROLLER ENG >> !workDirMulti!/!gameConfigFile!
					echo DIR "Digital Pad" >> !workDirMulti!/!gameConfigFile!
					echo ANA "Analog Pad" >> !workDirMulti!/!gameConfigFile!
					echo TL "Left Trigger" >> !workDirMulti!/!gameConfigFile!
					echo TR "Right Trigger" >> !workDirMulti!/!gameConfigFile!
					echo KA "Key A" >> !workDirMulti!/!gameConfigFile!
					echo KB "Key B" >> !workDirMulti!/!gameConfigFile!
					echo KX "Key X" >> !workDirMulti!/!gameConfigFile!
					echo KY "Key Y" >> !workDirMulti!/!gameConfigFile!
					echo ST "Start Button" >> !workDirMulti!/!gameConfigFile!
					echo END_CONTROLLER >> !workDirMulti!/!gameConfigFile!
				
				 )
				 
				if !bootMenu!==!dp3BootMenu! ( 
					set gameImageDst=!gameImageDst!.jpg
					if not exist !gameImageName! ( 
						set gameImageName=!workDirMulti!\game_logo.bmp
						echo No cover image found. Using default
					 )
					convert !gameImageName! -resize 200x200 -gravity center -extent 200x200 !workDirMulti!/DPWWW/IMG/!gameImageDst!
					::update content of DP3.ini file 
					echo.>> !workDirMulti!/DP3.ini
					echo [Launcher!index!] >> !workDirMulti!/DP3.ini
					echo AppUrl='http://www.dreamcastcn.com'  >> !workDirMulti!/DP3.ini
					echo AppDir='!gameFolderDst!'  >> !workDirMulti!/DP3.ini
					echo AppName='!bootFile!'  >> !workDirMulti!/DP3.ini
					echo AppOS=0  >> !workDirMulti!/DP3.ini
					echo AppDA=3  >> !workDirMulti!/DP3.ini
					echo 

					::update content of DPWWW/INDEX.HTM file
					echo ^<p^>^<a href="x-avefront://---.dream/proc/launch/!index!"^>^<img border="0" src="IMG/!gameImageDst!" width="200" height="200" align="middle"/^>^<br/^>!displayGameName!^</a^>^</p^>^</br^>^</br^>  >> !workDirMulti!/DPWWW/INDEX.HTM
				  )

			 )
			
		)
	
		if !bootMenu!==!dreamOnBootMenu! ( 
			echo END_PRODUCT_LIST>>!workDirMulti!/MENU.cfg
		 )


		if !bootMenu!==!dp3BootMenu! ( 
			echo. >> %workDirMulti%/DP3.ini
			echo [Game_ID] >> %workDirMulti%/DP3.ini
			echo. >> %workDirMulti%/DP3.ini
			echo XGame_ID='610-9999' >> %workDirMulti%/DP3.ini
			echo XGame_Ver='V0.999' >> %workDirMulti%/DP3.ini

			::finalize DPWWW/INDEX.HTM file
			echo ^</center^>^</div^>^</body^>^</html^> >> !workDirMulti!/DPWWW/INDEX.HTM
		  )


		set volumeName=%compilationFolder%
		set gameName=%parseGameNameResult%
		set gameFolder=%gameWorkingDir%
		set extractedFolder=%compilationFolder%

exit /b

:parse_game_name
set internal_val=%~1
call :parse_game_name_internal %internal_val: =_%
set parseGameNameResult=!parseGameNameResult!!val!
set "val=_"
exit /b

:parse_game_name_internal
for /f "tokens=1* delims=_-:;," %%i in ("%~1") do ( 
set val=%%i
set val=!val:~0,1!
set parseGameNameResult=%parseGameNameResult%%val%
call :parse_game_name_internal %%j
 ) 
 
exit /b

:cdi_to_data_data_folder
set filename=%1
set /a shouldCreateCDI=%2
set initialFileFormat=Audio-Data
if "%shouldCreateCDI%"=="" set shouldCreateCDI=1

set gameName=not set
for %%i in (%filename%) do ( 
set gameName=%%~ni
set gameFileName=%%~nxi
)

set gameName=%gameName: =_%

echo Selected Game Name is %gameName%

set gameFolder="%gameWorkingDir%\%gameName%"

mkdir %gameFolder%

cd %gameFolder%

set launchDir=%~dp0
set workDir=%cd%
echo workDir=%workDir%

::extracting CDI file content
"%launchDir%"\cdirip %filename% "%workDir%"

::reading LBA value for game data file
"%launchDir%"\cdirip %filename% -info>cdiripinfo.log
for /f "tokens=8 delims= " %%i in ('FINDSTR /C:"LBA" "%workDir%"\cdiripinfo.log') do set "lba=%%i"


::reading track number for game data file
type "%workDir%"\cdiripinfo.log | find /c "LBA">"%workDir%"\track_number.log
set /p trackNumber=< "%workDir%"\track_number.log
if "%keepFiles%"=="false" del "%workDir%"\track_number.log
if "%keepFiles%"=="false" del cdiripinfo.log
::add leading zero if needed
if 1%trackNumber% LSS 100 SET trackNumber=0%trackNumber%
set trackNumber=%trackNumber:~-2%

set sessionNumber=02
if "%trackNumber%"=="01" set sessionNumber=01
set isoFileName=s%sessionNumber%t%trackNumber:~-2%.iso
echo lba=%lba%
echo isoFileName=%isoFileName%

::if not exist fixed.iso if exist s01t01.bin set archiveForExtraction=s01t01.bin
if not exist *.iso if exist *.bin ( 
	echo.
	echo %gameFileName% is already in Data-Data format.
	echo Image in Audio-Data format expected.
	echo You can use %gameFileName% directly to burn it to CD-R.
	echo No processing for this file is required.
	echo.
	set initialFileFormat=Data-Data
	cd \..
	call :delete_folder '%gameFolder%' >nul
	::rd /s /q %gameFolder% >nul
	::del /f /q *.*
	::exit from function
	goto :cdi_to_data_data_folder_end
 )

::fix image so it's possible to extract it's content
(
echo %isoFileName%
echo %lba%
)|"%launchDir%\isofix"

set archiveForExtraction=fixed.iso
if not exist !archiveForExtraction! set archiveForExtraction=!isoFileName!


::extracting iso content
set extractedFolder=%gameName%
echo Extracting %archiveForExtraction% to plain folder... Please wait...
"%launchDir%\7z" x -y -o%extractedFolder% %archiveForExtraction%
::"%launchDir%\piso" extract %archiveForExtraction% / -od %extractedFolder%

::delete unnecessary files
if "%keepFiles%"=="false" ( 
	del %isoFileName%
	del *.wav
	del *.cue
	del %archiveForExtraction%
	del header.iso
 )

::set /p WAIT=Extracted. Press ENTER...

set bootFile=""

if exist %extractedFolder%\0.000 set bootFile=0.000
if exist %extractedFolder%\1ST_READ.BIN set bootFile=1ST_READ.BIN
if exist %extractedFolder%\0WINCEOS.BIN set bootFile=0WINCEOS.BIN
::if exist %extractedFolder%\1GUTH.BIN set bootFile=1GUTH.BIN
 
if %bootFile%=="" ( 
	echo Can't locate boot file ^(1ST_READ.BIN or 0WINCEOS.BIN^). Please pick boot file manually
	call :pick_dialog -filter "All Files (*.*)|*.*" -title "Pick boot file (equivalent of 1ST_READ.BIN or 0WINCEOS.BIN)"
	for %%i in (!fileNameList!) do set "bootFile=%%~nxi" 
)

set bootSector=IP.BIN
echo bootFile="%bootFile%"

if not exist bootfile.bin copy %extractedFolder%\IP.BIN
ren bootfile.bin %bootSector%
move %extractedFolder%\%bootFile% ".\" >nul

(
echo %bootFile%
echo %bootSector%
echo 0
)|"%launchDir%\binhack32"

move %bootFile% %extractedFolder% >nul
move IP.BIN %extractedFolder% >nul

echo Convertation to self booting folder for %gameName% finished
:cdi_to_data_data_folder_end

cd %launchDir%
exit /b

:bootable_cdi_from_folder
echo.
echo Creating CDI data-data file...
cd %gameFolder%
set volumeName=%gameName:~0,32%
echo volumeName=%volumeName%
if "%manualModification%"=="enabled" ( 
	set /p WAIT=It's time to modify selfboot folder's content. When Ready press ENTER to proceed with creation of CDI image...
)
echo.
echo Creating bootable ISO from folder...
"%launchDir%\mkisofs" -C 0,0 -G %extractedFolder%\IP.BIN -V %volumeName% -joliet -rock -l -o data.iso %extractedFolder% >nul
call :delete_folder %extractedFolder% > nul
echo.
echo Creating CDI from ISO... Please Wait...
"%launchDir%\cdi4dc" data.iso %gameName%.cdi -d >nul
echo Creation of %gameName%.cdi is finished.
echo Full path to CDI image is %cd%\%gameName%.cdi

::delete unnecessary files
if "%keepFiles%"=="false" del data.iso

cd %launchDir%
exit /b

:delete_folder
if "%keepFiles%"=="false" ( 
	set folderToDelete=%~1
	set folderToDelete=!folderToDelete:"=!
	set folderToDelete=!folderToDelete:'=!
	echo Deleting folder !folderToDelete!
	del /s /f /q "!folderToDelete!" >nul
	for /f %%f in ('dir /ad /b "!folderToDelete!"') do rd /s /q "!folderToDelete!"\%%f >nul
	rd /s /q "!folderToDelete!" >nul
 )
exit /b
