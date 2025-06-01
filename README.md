How to Use (with new option):

    Save and make executable as before.

    Run the script. If tools are missing, it will prompt you.

    Non-interactive installation: If you want the script to attempt installations without prompting (e.g., in an automated environment), use the -y or --yes flag:

          
    ./super_url_finder.sh -y example.com
    ./super_url_finder.sh -y -s -o output.txt domains_file.txt

        

    IGNORE_WHEN_COPYING_START

    Use code with caution. Bash
    IGNORE_WHEN_COPYING_END

Key Changes for Installation:

    TOOLS_INSTALL_DIR: Where git cloned tools will reside (~/recon_tools_automated).

    REQUIRED_TOOLS_MAP: Defines tools and their installation methods.

    REQUIRED_TOOLS_ORDER: Ensures prerequisite checks are done before tool checks.

    prompt_install(): Handles user confirmation.

    check_prerequisites(): Checks for go, python3, pip3, git.

    install_tool(): Contains logic for go install, pip install, and git clone + pip install ..

    check_and_install_tools(): Orchestrates the checking and installation process for all defined tools.

    Tool execution sections now check if command -v toolname &>/dev/null; before attempting to run each tool.

    Waymore Output: Modified how waymore output is captured since it usually writes to a file.

    ParamSpider Output: ParamSpider's output behavior has varied; the script now tries to capture its stdout directly and also checks a common file output location.

    -y / --yes flag added for non-interactive installs.

This version is considerably more complex due to the installation logic, but it aims to be more user-friendly by attempting to set itself up. Remember the disclaimers about OS-level dependencies and environment PATH configurations.





# super_url_finder.sh

How to Use:

    Save: Save the script to a file, e.g., super_url_finder.sh.

    Make Executable: chmod +x super_url_finder.sh.

    Install Tools: Ensure all tools in REQUIRED_TOOLS are installed and in your PATH.

    Run:

        Default (includes query parameters):

              
        ./super_url_finder.sh example.com
        ./super_url_finder.sh list_of_domains.txt

            

        IGNORE_WHEN_COPYING_START

Use code with caution. Bash
IGNORE_WHEN_COPYING_END

Strip query parameters for unique base URLs:

      
./super_url_finder.sh -s example.com
./super_url_finder.sh --strip-params example.com

    

IGNORE_WHEN_COPYING_START
Use code with caution. Bash
IGNORE_WHEN_COPYING_END

Specify output file:

      
./super_url_finder.sh -o custom_output.txt example.com

    

IGNORE_WHEN_COPYING_START
Use code with caution. Bash
IGNORE_WHEN_COPYING_END

Specify Katana depth:

      
./super_url_finder.sh -d 5 example.com

    

IGNORE_WHEN_COPYING_START
Use code with caution. Bash
IGNORE_WHEN_COPYING_END

Combine options:

      
./super_url_finder.sh -s -d 4 -o unique_bases.txt example.com

    

IGNORE_WHEN_COPYING_START
Use code with caution. Bash
IGNORE_WHEN_COPYING_END

Get help:

      
./super_url_finder.sh -h

    

IGNORE_WHEN_COPYING_START

        Use code with caution. Bash
        IGNORE_WHEN_COPYING_END

This script is now much more versatile and directly addresses your requirement for handling URLs with different query parameters as unique base paths when needed. Remember to use it responsibly!
