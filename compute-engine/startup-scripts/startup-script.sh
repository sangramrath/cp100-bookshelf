#! /bin/bash
# Copyright 2016 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# [START startup]
set -v

# Talk to the metadata server to get the project id
PROJECTID=$(curl -s "http://metadata.google.internal/computeMetadata/v1/project/project-id" -H "Metadata-Flavor: Google")

# Install logging monitor. The monitor will automatically pickup logs sent to
# syslog.
# [START logging]
curl -s "https://storage.googleapis.com/signals-agents/logging/google-fluentd-install.sh" | bash
service google-fluentd restart &
# [END logging]

# Install dependencies from apt
apt-get update
apt-get install -yq \
    git build-essential supervisor python3 python3-dev python3-pip libffi-dev \
    libssl-dev

# Create a pythonapp user. The application will run as this user.
useradd -m -d /home/pythonapp pythonapp

# pip from apt is out of date, so make it update itself and install virtualenv.
pip3 install --upgrade pip virtualenv

# Get the source code from the Google Cloud Repository
# git requires $HOME and it's not set during the startup script.
export HOME=/root
git config --global credential.helper gcloud.sh
git clone https://source.developers.google.com/p/$PROJECTID /opt/app

# Replace the project ID placeholder in config.py
sed -i s/your-project-id/"$PROJECTID"/ /opt/app/compute-engine/config.py

# Install app dependencies
virtualenv /opt/app/compute-engine/env
/opt/app/compute-engine/env/bin/pip3 install -r /opt/app/compute-engine/requirements.txt

# Make sure the pythonapp user owns the application code
chown -R pythonapp:pythonapp /opt/app

# Configure supervisor to start gunicorn inside of our virtualenv and run the
# application.
cat >/etc/supervisor/conf.d/python-app.conf << EOF
[program:pythonapp]
directory=/opt/app/compute-engine
command=/opt/app/compute-engine/env/bin/gunicorn main:app --bind 0.0.0.0:8080
autostart=true
autorestart=true
user=pythonapp
# Environment variables ensure that the application runs inside of the
# configured virtualenv.
environment=VIRTUAL_ENV="/opt/app/env/compute-engine",PATH="/opt/app/compute-engine/env/bin",\
    HOME="/home/pythonapp",USER="pythonapp"
stdout_logfile=syslog
stderr_logfile=syslog
EOF

supervisorctl reread
supervisorctl update

# Application should now be running under supervisor
# [END startup]
