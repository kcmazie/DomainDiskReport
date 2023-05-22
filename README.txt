# DomainDiskReport
This script uses WMI to poll the current domain and extract disk statistics.


         File Name : DomainDiskReport.ps1
   Original Author : Kenneth C. Mazie (kcmjr @ kcmjr.com)
                   :
       Description : This script uses WMI to poll the current domain and extract
                   : disk statistics. Output is gathered in HTML format and emailed
                   : to a list of recipients. Output can be all systems (full)
                   : or only systems that are below preset threshold (brief).
                   :
         Arguments : Named commandline parameters: (all are optional)
                   : "-display" - Displays console output during run.
                   : "-debug" - Switches email recipient and target criteria. Also dumps HTML output to script folder
                   : "-detail" - Can be set to "full" or "brief". Default to "brief".
                   : "-mode" - Can be "all", "pc", "video", or "server". Defaults to "all" which polls all 3.
                   : Note that mode setting has been moved to the XML file.
                   :
             Notes : Allows setting a threshold of the lowest remaining space. Colors all others in red.
                   : Numerous parameters are adjustable from within the main function.
                   : !!! -- Best run from a scheduled job as a domain admin user -- !!!
                   :
          Warnings : None
                   :
             Legal : Public Domain. Modify and redistribute freely. No rights reserved.
                   : SCRIPT PROVIDED "AS IS" WITHOUT WARRANTIES OR GUARANTEES OF
                   : ANY KIND. USE AT YOUR OWN RISK. NO TECHNICAL SUPPORT PROVIDED.
                   : That being said please let me know if you find bugs!
                   :
           Credits : Code snippets and/or ideas came from many sources around the web.
                   :
    Last Update by : Kenneth C. Mazie (email kcmjr AT kcmjr.com for comments or to report bugs)
   Version History : v1.00 - 05-03-14 - Original
    Change History : v2.00 - 11-01-14 - Changed HTML formatting. Added commandline options.
                   : v2.01 - 12-10-14 - Changed input arguments to be named
                   : v2.02 - 02-11-15 - Added Win8x detection. Moved notes to bottom of report.
                   : v3.00 - 05-28-15 - Numerous changes. Retooled report wording. Added ignore list for
                   : large data drives. Added video server option.
                   : v3.01 - 10-20-15 - Minor edits, updated syntax.
                   : v4.00 - 02-19-16 - Fixed issue detecting PC and Video. Re-enabled video check.
                   : v4.10 - 07-22-16 - Adjusted "woo-hoo" message locations and function.
                   : v4.20 - 01-03-18 - Adjusted external config file, changed console formatting
                   : v4.30 - 05-18-18 - Excluded workstations since VDIs are no longer in use.
                   : Fixed missing credential call on get-adcomputers (line 325)
                   : v4.40 - 06-12-18 - Added support for server 2016
                   : v4.41 - 06-26-18 - Fixed minor bug with output.
                   : v4.50 - 06-29-18 - Output bug still exists. Now corrected. Adjusted for Win10,
                   : removed Win 7 & 8. Altered output colors.
                   : v4.60 - 07-20-18 - Fixed another output bug (nothing found message not in output)
                   : v4.70 - 07-23-18 - Added ping failure to "brief" output. Altered no ping and failure notations.
                   : v4.80 - 08-16-18 - Added multiple connectivity tests
                   : v4.81 - 01-10-19 - Fixed typo in credential. Changed domain detecion.
                   :
