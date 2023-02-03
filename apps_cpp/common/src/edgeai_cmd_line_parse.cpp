/*
 *  Copyright (C) 2021 Texas Instruments Incorporated - http://www.ti.com/
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *
 *    Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 *    Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the
 *    distribution.
 *
 *    Neither the name of Texas Instruments Incorporated nor the names of
 *    its contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 *  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 *  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 *  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 *  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 *  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 *  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 *  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* Standard headers. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <filesystem>

/* Module headers. */
#include <common/include/edgeai_cmd_line_parse.h>

namespace ti::edgeai::common
{
static void showUsage(const char *name)
{
    printf("# \n");
    printf("# %s PARAMETERS [OPTIONAL PARAMETERS]\n", name);
    printf("# POSITIONAL PARAMETERS:\n");
    printf("#  config_file - Path to the configuration file.\n");
    printf("# OPTIONAL PARAMETERS:\n");
    printf("#  [--no-curses  |-n Disable curses report.]\n");
    printf("#  [--log-level  |-l Logging level to enable. [0: DEBUG 1:INFO 2:WARN 3:ERROR]. Default is 2.\n");
    printf("#  [--dump-dot   |-d Dump Gstreamer Pipeline as dot file.]\n");
    printf("#  [--verbose    |-v]\n");
    printf("#  [--help       |-h]\n");
    printf("# \n");
    printf("# (C) Texas Instruments 2021\n");
    printf("# \n");
    printf("# EXAMPLE:\n");
    printf("#    %s ../configs/single_input_single_inference.yaml.\n", name);
    printf("# \n");
    exit(0);
}

void
CmdlineArgs::parse(int32_t        argc,
                   char          *argv[])
{
    int32_t longIndex;
    int32_t opt;
    static struct option long_options[] = {
        {"help",      no_argument,       0, 'h' },
        {"verbose",   no_argument,       0, 'v' },
        {"no-curses", no_argument,       0, 'n' },
        {"dump-dot",  no_argument,       0, 'd' },
        {"log-level", required_argument, 0, 'l' },
        {0,           0,                 0,  0  }
    };

    while ((opt = getopt_long(argc, argv,"-hdvnl:",
                   long_options, &longIndex )) != -1)
    {
        switch (opt)
        {
            case 1 :
                configFile = optarg;
                break;

            case 'l' :
                logLevel = static_cast<LogLevel>(strtol(optarg, NULL, 0));
                break;

            case 'n' :
                enableCurses = false;
                break;

            case 'v' :
                verbose = true;
                break;

            case 'd' :
                dumpDot = true;
                break;

            case 'h' :
            default:
                showUsage(argv[0]);
                exit(-1);

        } // switch (opt)

    } // while ((opt = getopt_long(argc, argv

    // Check if the specified configuration file exists
    if (!std::filesystem::exists(configFile))
    {
        LOG_ERROR("The file [%s] does not exist.\n",
                  configFile.c_str());
        exit(-1);
    }

    /* Set the log level. */
    logSetLevel(logLevel);

    return;

}

} // namespace ti::edgeai::common

