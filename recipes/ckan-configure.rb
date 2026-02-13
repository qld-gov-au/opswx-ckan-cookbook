#
# Copyright 2021, Queensland Government
#
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

include_recipe "datashades::default-configure"

# Fix Amazon PYTHON_INSTALL_LAYOUT so items are installed in sites/packages not distr/packages
#
bash "Fix Python Install Layout" do
    user 'root'
    code <<-EOS
    sed -i 's~setenv PYTHON_INSTALL_LAYOUT "amzn"~# setenv PYTHON_INSTALL_LAYOUT "amzn"~g' /etc/profile.d/python-install-layout.csh
    sed -i 's~export PYTHON_INSTALL_LAYOUT="amzn"~# export PYTHON_INSTALL_LAYOUT="amzn"~g' /etc/profile.d/python-install-layout.sh
    unset PYTHON_INSTALL_LAYOUT
    EOS
    not_if "grep '# export PYTHON_INSTALL_LAYOUT' /etc/profile.d/python-install-layout.sh"
end
