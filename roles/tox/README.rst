Runs tox for a project

This role overrides Python packages installed into tox environments with
corresponding Zuul sibling projects and runs tox tests as follows:

#. Create tox environments.
#. Get Python sibling package names for sibling projects created by
   Zuul (using ``required-projects`` job variable). Package names are
   searched in following sources:

   * ``setup.cfg`` of *pbr* projects,
   * ``setup.py``,
   * ``tox_package_name`` role variable.

#. Remove sibling packages from tox environments.
#. Create temporary constraints file, lines for sibling packages are
   removed.
#. Install sibling packages from Zuul projects into tox environments
   with temporary constraints file.
#. Run tox tests.

**Role Variables**

.. zuul:rolevar:: tox_environment
   :type: dict

   Environment variables to pass in to the tox run.

.. zuul:rolevar:: tox_envlist

   Comma separated string with test environments tox should run.
   ``ALL`` runs all test environments while an empty string runs
   all test environments configured with ``envlist`` in tox.

.. zuul:rolevar:: tox_executable
   :default: tox

   Location of the tox executable.

.. zuul:rolevar:: tox_config_file

   Path to a tox configuration file, or directory containing a
   ``tox.ini`` file. Will be provided to tox via its ``-c``
   command-line option if set.

.. zuul:rolevar:: tox_extra_args
   :default: -vv --skip-missing-interpreters=false

   String of extra command line options to pass to tox.

.. zuul:rolevar:: tox_constraints_file

   Path to a pip constraints file. Will be provided to tox via
   ``TOX_CONSTRAINTS_FILE`` (deprecated but currently still supported
   name is ``UPPER_CONSTRAINTS_FILE``) environment variable if it
   exists.

.. zuul:rolevar:: tox_install_siblings
   :default: true

   Flag controlling whether to attempt to install python packages from any
   other source code repos zuul has checked out. Defaults to True.

.. zuul:rolevar:: tox_package_name

   Allows a user to setup the package name to be used by tox, over reading
   a setup.cfg file in the project.

.. zuul:rolevar:: zuul_work_dir
   :default: {{ zuul.project.src_dir }}

   Directory to run tox in.
