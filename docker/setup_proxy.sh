#!/bin/bash

#  Copyright (C) 2021 Texas Instruments Incorporated - http://www.ti.com/
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#    Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#    Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the
#    distribution.
#
#    Neither the name of Texas Instruments Incorporated nor the names of
#    its contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
#  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
#  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
#  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
#  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
#  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
#  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

if [ "$USE_PROXY" = "1" ]; then

	# env variables
	source ~/proxy/envs.sh

	# docker proxy
	mkdir -p ~/.docker
	ln -snf ~/proxy/config.json ~/.docker/config.json

	# apt proxy
	ln -snf ~/proxy/apt.conf /etc/apt/apt.conf

	# wget proxy
	ln -snf ~/proxy/.wgetrc ~/.wgetrc

	# pip3 proxy
	mkdir -p ~/.config/pip/
	ln -snf ~/proxy/pip.conf ~/.config/pip/pip.conf

	# git proxy
   	ln -snf ~/proxy/.gitconfig ~/.gitconfig
	ln -snf ~/proxy/git-proxy.sh ~/git-proxy.sh

	# curl proxy
	ln -snf ~/proxy/.curlrc ~/.curlrc

else
	unset http_proxy https_proxy ftp_proxy HTTP_PROXY HTTPS_PROXY FTP_PROXY noproxy
	rm -rf ~/.docker/config.json
	rm -rf /etc/apt/apt.conf
	rm -rf ~/.wgetrc
	rm -rf ~/.config/pip/pip.conf
	rm -rf ~/.gitconfig ~/git-proxy.sh
	rm -rf ~/.curlrc
fi
