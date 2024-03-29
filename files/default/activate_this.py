"""By using execfile(this_file, dict(__file__=this_file)) you will
activate this virtualenv environment.

This can be used when you must use an existing Python interpreter, not
the virtualenv bin/python
"""

try:
    __file__
except NameError:
    raise AssertionError(
        "You must run this like execfile('path/to/activate_this.py',"
        " dict(__file__='path/to/activate_this.py'))")
import sys
import os

import site

old_os_path = os.environ.get('PATH', '')
this_dir = os.path.dirname(os.path.abspath(__file__))
os.environ['PATH'] = this_dir + os.pathsep + old_os_path
base = os.path.dirname(this_dir)
if sys.platform == 'win32':
    site_packages = os.path.join(base, 'Lib', 'site-packages')
else:
    site_packages = os.path.join(
        base, 'lib', 'python%s' % sys.version[:3], 'site-packages')
    site_packages64 = os.path.join(
        base, 'lib64', 'python%s' % sys.version[:3], 'site-packages')
prev_sys_path = list(sys.path)
site.addsitedir(site_packages)
site.addsitedir(site_packages64)
sys.real_prefix = sys.prefix
sys.prefix = base
# Move the added items to the front of the path:
new_sys_path = []
for item in list(sys.path):
    if item not in prev_sys_path:
        new_sys_path.append(item)
        sys.path.remove(item)
sys.path[:0] = new_sys_path
