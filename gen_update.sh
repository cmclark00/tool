#!/bin/sh

# Here are all the variables that can and should be changed according to your environment
# or what type of update this needs to be generated for.

# Update the following to your specific requirements and repository location and folder names
REPO_ROOT="${REPO_ROOT:-Repo/MustardOS}"
REPO_FRONTEND="${REPO_FRONTEND:-frontend}"
REPO_INTERNAL="${REPO_INTERNAL:-internal}"
REPO_LANGUAGE="${REPO_LANGUAGE:-language}"
REPO_APPLICATION="${REPO_APPLICATION:-application}"
REPO_EMULATOR="${REPO_EMULATOR:-emulator}"

# PLEASE NOTE: If you are an active contributor please add yourself to the list at the bottom of the script!

# Anything below this line should not be modified unless required. Seriously!
# ------------------------------------------------------------------------------------

# Check for all the required commands we'll be using from here on in
for CMD in git rsync zip unzip sed pv; do
	if ! command -v "$CMD" >/dev/null 2>&1; then
		printf "Error: Missing required command '%s'\n" "$CMD" >&2
		exit 1
	fi
done

# Exit immediately if a command exits with a non-zero status
set -e

REL_DIR="$(pwd)"
CHANGE_DIR="$REL_DIR/.CHANGE.$$"
UPDATE_DIR="$REL_DIR/.UPDATE.$$"
MU_UDIR="$REL_DIR/UPDATE"
MU_RARC="$REL_DIR/UPDATE/REC_ARC"
mkdir -p "$MU_RARC"

# These have to be in a central binded mount otherwise they will be ignored...
STORAGE_LOCS="bios language"

# Ensure temporary directories are cleaned up on exit - also on ctrl+c and anything else
trap 'rm -rf "$CHANGE_DIR" "$UPDATE_DIR" "$HOME/$REPO_ROOT/$REPO_INTERNAL/update.sh" "$MU_RARC"' EXIT INT TERM

# Check for at least two arguments - commits and then mount points
if [ "$#" -lt 2 ]; then
	printf "Usage: %s <FROM_COMMIT> <MOUNT_POINT>\n" "$0" >&2
	exit 1
fi

printf "\n=============== \033[1mmuOS Update Automation Utility (MUAU)\033[0m ==============\n\n"

TR_RENAME() {
	TR_DEST="$HOME/$REPO_ROOT/$REPO_INTERNAL/init/MUOS/language/$2"
	printf "\033[1mUpdating '\033[0m%s\033[1m' to '\033[0m%s\033[1m'\033[0m\n" "$1" "$TR_DEST"
	cp "$1" "$TR_DEST" || printf "\033[1m\t- Failed on '%s'\033[0m\n" "$1"
}

cd "$HOME/$REPO_ROOT/$REPO_LANGUAGE" || {
	printf "Language repository missing (%s)\n" "$REPO_ROOT/$REPO_LANGUAGE"
	exit 1
}

printf "\033[1mUpdating languages from '%s' repository\033[0m\n" "$REPO_LANGUAGE"
git pull
printf "\n"

cd "mux" || {
	printf "Languages for component 'muX' missing (%s)\n" "$REPO_ROOT/$REPO_LANGUAGE/mux"
	exit 1
}

# Read the mappings from the file and call TR_RENAME for each entry
while IFS=":" read -r WL_SOURCE FULL_NAME; do
	[ -z "$WL_SOURCE" ] && continue
	TR_RENAME "${WL_SOURCE}.json" "${FULL_NAME}.json"
done <"$HOME/$REPO_ROOT/$REPO_LANGUAGE/tr_map.txt"

cd "$REL_DIR"

MOUNT_POINT="$2"
FROM_COMMIT="$1"

# Version the archive should be set to and the build ID that is required for the update to work
VERSION="${VERSON:-"$(head -n 1 "$HOME/$REPO_ROOT/$REPO_INTERNAL/config/system/version")"}"
FROM_BUILDID="${FROM_BUILDID:-$(git rev-parse --short "$FROM_COMMIT")}"

# Get the latest internal commit number - we don't really care much for the frontend commit ID :D
cd "$HOME/$REPO_ROOT/$REPO_INTERNAL" || {
	printf "Internal repository missing (%s)" "$REPO_ROOT/$REPO_INTERNAL"
	exit 1
}

TO_COMMIT="$(git rev-parse --short HEAD)"
COMMIT_DATE="$(git show -s --format=%cI "$1")"

git log --since="$COMMIT_DATE" --pretty=format:"%s%n%b" >"$MU_UDIR/changelog-$REPO_INTERNAL.txt"

# Now that we have the date from the commit given lets go into the frontend repo and grab the changes there too!
cd "$HOME/$REPO_ROOT/$REPO_FRONTEND" || {
	printf "Frontend repository missing (%s)" "$REPO_ROOT/$REPO_FRONTEND"
	exit 1
}

git log --since="$COMMIT_DATE" --pretty=format:"%s%n%b" >>"$MU_UDIR/changelog-$REPO_FRONTEND.txt"

cd "$REL_DIR"

ARCHIVE_NAME="muOS-$VERSION-$TO_COMMIT-UPDATE.muxupd"

# Create temporary directory structure for both update archive and diff file stuff
mkdir -p "$MU_UDIR" "$CHANGE_DIR" "$UPDATE_DIR/opt/muos/frontend" \
	"$UPDATE_DIR/opt/muos/default/MUOS/info/config" \
	"$UPDATE_DIR/opt/muos/default/MUOS/info/name" \
	"$UPDATE_DIR/opt/muos/default/MUOS/retroarch" \
	"$UPDATE_DIR/opt/muos/default/MUOS/theme" \
	"$UPDATE_DIR/mnt/$MOUNT_POINT/MUOS"

printf "\n"

UPDATE_TASKS="
Frontend|$HOME/$REPO_ROOT/$REPO_FRONTEND/bin/|$UPDATE_DIR/opt/muos/frontend/
Applications|$HOME/$REPO_ROOT/$REPO_APPLICATION/|$UPDATE_DIR/mnt/$MOUNT_POINT/MUOS/application/
Emulators|$HOME/$REPO_ROOT/$REPO_EMULATOR/|$UPDATE_DIR/mnt/$MOUNT_POINT/MUOS/emulator/
"

printf "%s" "$UPDATE_TASKS" | while IFS='|' read -r COMPONENT SRC DST; do
	# Skip over empty lines like the first and last ones. I like to keep things tidy!
	[ -z "$COMPONENT" ] || [ -z "$SRC" ] || [ -z "$DST" ] && continue

	printf "\t\033[1m- Updating muOS %s\033[0m\n" "$COMPONENT"
	rsync -a --info=progress2 \
		--exclude='.git/' \
		--exclude='.gitmodules' \
		--exclude='LICENSE' \
		--exclude='README.md' \
		--exclude='**/.gitkeep' \
		"$SRC" "$DST"
	printf "\n"
done

printf "\t\033[1m- Updating muOS Defaults\033[0m\n"

UPDATE_DEFAULTS="
$HOME/$REPO_ROOT/$REPO_INTERNAL/init/MUOS/info/config/|$UPDATE_DIR/mnt/$MOUNT_POINT/MUOS/info/config/
$HOME/$REPO_ROOT/$REPO_INTERNAL/init/MUOS/info/name/|$UPDATE_DIR/mnt/$MOUNT_POINT/MUOS/info/name/
$HOME/$REPO_ROOT/$REPO_INTERNAL/init/MUOS/retroarch/|$UPDATE_DIR/mnt/$MOUNT_POINT/MUOS/retroarch/
$HOME/$REPO_ROOT/$REPO_INTERNAL/init/MUOS/theme/|$UPDATE_DIR/mnt/$MOUNT_POINT/MUOS/theme/
"

echo "$UPDATE_DEFAULTS" | while IFS='|' read -r SRC DST; do
	[ -z "$SRC" ] || [ -z "$DST" ] && continue

	mkdir -p "$DST"
	rsync -a --info=progress2 "$SRC" "$DST"
done

printf "\n\t\033[1m- Removing Leftover Files\033[0m\n"
find "$UPDATE_DIR/." -name ".gitkeep" -delete

# Let's go to the internal directory - away we go!
cd "$HOME/$REPO_ROOT/$REPO_INTERNAL"

# Grab the file diff of all changes based on commit to commit
#
# Filter out init/MUOS/theme/active to avoid messing up the active theme
git diff-tree -t --no-renames "$FROM_COMMIT" "$TO_COMMIT" |
	grep -Ev '^[^	]*	init/MUOS/theme/active($|/)' >"$CHANGE_DIR/commit.txt"

# Split changes into added/modified files, deleted files, and deleted directories.
#
# Mode 10xxxx is file, 04xxxx is directory. (See https://stackoverflow.com/a/8347325/152208)
# See also "raw output format" in `man git-diff-tree` for more details
sed -En 's/^:[^ ]* 10[^\t]* (A|M)\t//p' "$CHANGE_DIR/commit.txt" >"$CHANGE_DIR/archived.txt"
sed -En 's/^:10[^\t]* D\t//p' "$CHANGE_DIR/commit.txt" >"$CHANGE_DIR/deleted_files.txt"
sed -En 's/^:04[^\t]* D\t//p' "$CHANGE_DIR/commit.txt" >"$CHANGE_DIR/deleted_dirs.txt"

# Create 'update.sh' file at /opt/ so the archive manager can run it
printf '#!/bin/sh\n' >"update.sh"

# Check for any deleted files and directories
GEN_DELETES() {
	TEST="$1" # Existence condition to test before removing (-f, -d, ...)
	CMD="$2"  # Command to perform the removal (rm -f, rmdir, ...)

	while IFS= read -r FILE; do
		case "$FILE" in
			init/*)
				# Generate deletion commands for the storage mount
				MATCH_FOUND=0
				for S_LOC in $STORAGE_LOCS; do
					# Check if the directory part of the file matches STORAGE_LOCS
					if dirname "$FILE" | grep -q "$S_LOC"; then
						# If matched, generate deletion command with the storage path
						D_PATH="/run/muos/storage/$S_LOC/${FILE#init/MUOS/"$S_LOC"}"
						SAFE_D_PATH=$(printf '%s' "$D_PATH" | sed 's/["\\]/\\&/g')
						printf '[ %s "%s" ] && %s "%s" 2>/dev/null\n' "$TEST" "$SAFE_D_PATH" "$CMD" "$SAFE_D_PATH"
						MATCH_FOUND=1
						break
					fi
				done

				# If no match in STORAGE_LOCS, fall back to the default path
				if [ "$MATCH_FOUND" -eq 0 ]; then
					D_PATH="/mnt/$MOUNT_POINT/${FILE#init/}"
					SAFE_D_PATH=$(printf '%s' "$D_PATH" | sed 's/["\\]/\\&/g')
					printf '[ %s "%s" ] && %s "%s" 2>/dev/null\n' "$TEST" "$SAFE_D_PATH" "$CMD" "$SAFE_D_PATH"
				fi
				;;
			*)
				# For non-init files, default deletion path
				D_PATH="/opt/muos/$FILE"
				SAFE_D_PATH=$(printf '%s' "$D_PATH" | sed 's/["\\]/\\&/g')
				printf '[ %s "%s" ] && %s "%s" 2>/dev/null\n' "$TEST" "$SAFE_D_PATH" "$CMD" "$SAFE_D_PATH"
				;;
		esac
	done
}

if [ -s "$CHANGE_DIR/deleted_files.txt" ]; then
	printf '\n' >>"update.sh"
	GEN_DELETES -f 'rm -f' <"$CHANGE_DIR/deleted_files.txt" >>"update.sh"
fi

if [ -s "$CHANGE_DIR/deleted_dirs.txt" ]; then
	printf '\n' >>"update.sh"
	# Print rmdir commands in reverse so we remove foo/bar before foo
	sort -r "$CHANGE_DIR/deleted_dirs.txt" | GEN_DELETES -d 'rmdir' >>"update.sh"
fi

# Remove the temporary copy of the inner archive
# Mark archive as installed (since we don't ever return to extract.sh)
{
	printf "\nrm -f \"/opt/%s\"\n" "$ARCHIVE_NAME"
	printf "touch \"/mnt/%s/MUOS/update/installed/%s.done\"\n" "$MOUNT_POINT" "$ARCHIVE_NAME"
	printf "\n/opt/muos/script/mux/quit.sh reboot frontend\n"
	printf "\nwhile read -r _; do :; done\n"
} >>"update.sh"

# Copy added and modified files into the '.update' directory
while IFS= read -r FILE; do
	if [ -e "$FILE" ]; then
		case "$FILE" in
			init/*)
				FILE_COPIED=0
				S_=0
				for _ in $STORAGE_LOCS; do
					S_LOC=$(echo "$STORAGE_LOCS" | cut -d' ' -f$((S_ + 1)))

					# Check if the directory part of the file matches STORAGE_LOCS
					if dirname "$FILE" | grep -q "$S_LOC"; then
						# Replace only the directory part, not the file name!
						D_PATH="$UPDATE_DIR/run/muos/storage/$S_LOC/${FILE#init/MUOS/"$S_LOC"}"
						mkdir -p "$(dirname "$D_PATH")"
						cp "$FILE" "$D_PATH"
						FILE_COPIED=1
						break
					fi

					S_=$((S_ + 1))
				done

				# If nothing matches in STORAGE_LOCS then fall back to the default path of the given mount
				if [ "$FILE_COPIED" -eq 0 ]; then
					D_PATH="$UPDATE_DIR/mnt/$MOUNT_POINT/${FILE#init/}"
					mkdir -p "$(dirname "$D_PATH")"
					cp "$FILE" "$D_PATH"
				fi
				;;
			*)
				D_PATH="$UPDATE_DIR/opt/muos/$FILE"
				mkdir -p "$(dirname "$D_PATH")"
				cp "$FILE" "$D_PATH"
				;;
		esac
	else
		printf "\t\033[1mWarning: File '%s' does not exist and will not be copied!\033[0m\n" "$FILE"
	fi
done <"$CHANGE_DIR/archived.txt"

# Update version and build and copy update.sh to the correct directories
mkdir -p "$UPDATE_DIR/opt/muos/config/system"
printf '%s' "$(printf %s "$VERSION" | tr - ' ')" >"$UPDATE_DIR/opt/muos/config/system/version"
printf '%s' "$TO_COMMIT" >"$UPDATE_DIR/opt/muos/config/system/build"
chmod +x "update.sh"
cp "update.sh" "$UPDATE_DIR/opt/update.sh"

cd "$UPDATE_DIR" || exit 1
find . -name ".gitkeep" -delete
chmod -R 755 .
chown -R "$(whoami):$(whoami)" ./*

mkdir -p "$MU_RARC/opt/"

ZIP_COMMENT="$VERSION ($TO_COMMIT)"

# It's compression time!
printf "\n\033[1mCreating muOS update archive\033[0m\n"
echo "$ZIP_COMMENT" |
	zip -q9r -z - . |
	pv -bep --width 75 >"$MU_RARC/opt/$ARCHIVE_NAME"

cd "$REL_DIR"

# Time to make a recursive archive so that we can check for version information before we try to update!
# Yes I could have done an EOF but they irk me! So fuck you, printf it is :D
{
	printf "#!/bin/sh\n"
	printf "\nCURR_BUILDID=\$(cat /opt/muos/config/system/build)"
	printf "\ncase \"\$CURR_BUILDID\" in\n"
	printf "\t%s)\n" "$FROM_BUILDID"
	printf "\t\t/opt/muos/script/mux/extract.sh \"/opt/%s\"\n" "$ARCHIVE_NAME"
	printf "\n\t\twhile read -r _; do :; done\n\n"
	printf "\t\t;;\n"
	printf "\t*)\n"
	printf "\t\trm -f \"/opt/%s\"\n\n" "$ARCHIVE_NAME"
	printf "\t\techo \"This update is for BUILD ID of '%s' only!\"\n" "$FROM_BUILDID"
	printf "\t\techo \"You are currently on '\$CURR_BUILDID'\"\n"
	printf "\t\techo \"\"\n"
	printf "\t\techo \"If this is a genuine error, please report it!\"\n"
	printf "\n\t\tsleep 10\n\n"
	printf "\t\t;;\n"
	printf "esac\n"
} >"$MU_RARC/opt/update.sh"

cd "$MU_RARC" || exit 1

printf "\n\033[1mCreating recursive archive for muOS version checking\033[0m\n"
echo "$ZIP_COMMENT" |
	zip -q0r -z - . |
	pv -bep --width 75 >"$MU_UDIR/$ARCHIVE_NAME"

cd "$REL_DIR"

printf "\n\033[1mArchive created at\033[0m\n\t%s\n" "$MU_UDIR/$ARCHIVE_NAME"

: >"$MU_UDIR/contributor.txt"

# Get the commits since the date and extract the GitHub user names - API only gives 60 per hour... hmm?
UPDATE_CONTRIBUTORS() {
	REPO="$1"

	# Hopefully we aren't going to get 5 pages (that's over 500 commits) for updates...
	for PAGE in $(seq 1 5); do
		# Record the initial file size of contributor.txt
		INITIAL_SIZE=$(wc -c <"$MU_UDIR/contributor.txt" 2>/dev/null || echo 0)

		# Fetch contributors from GitHub with the author login (hopefully this is right) and append to contributor.txt
		curl -s "https://api.github.com/repos/MustardOS/$REPO/commits?since=$COMMIT_DATE&page=$PAGE&per_page=100" |
			jq -r '.[].author.login' | sort -u >>"$MU_UDIR/contributor.txt"

		# Check the new file size and compare it with the initial because we are checking pages.
		# If we go to the next page and the file size isn't different then we just move on.
		NEW_SIZE=$(wc -c <"$MU_UDIR/contributor.txt" 2>/dev/null || echo 0)
		[ "$INITIAL_SIZE" -eq "$NEW_SIZE" ] && break
	done
}

GH2D_REPLACE() {
	GH2D_FILE=$(mktemp)

	sed -i "s|${1}|${2}|g" "$MU_UDIR/contributor.txt"
	tr " " "\n" <"$MU_UDIR/contributor.txt" | sort -u | tr "\n" " " >"$GH2D_FILE"

	sed -i 's/[[:space:]]*$//' "$GH2D_FILE"
	mv "$GH2D_FILE" "$MU_UDIR/contributor.txt"
}

# Update the contributor list
UPDATE_CONTRIBUTORS "internal"
UPDATE_CONTRIBUTORS "frontend"

# Add to this as required (GitHub username -> Discord username)
GH2D_REPLACE abretro @__krt__
GH2D_REPLACE AchillesPDX @achillespdx
GH2D_REPLACE antiKk @antiKk
GH2D_REPLACE bgelmini @bgelmini
GH2D_REPLACE booYah187 @mattyj513
GH2D_REPLACE cgimenes @mardeoli
GH2D_REPLACE cmclark00 @koolkidkorey
GH2D_REPLACE CometHunter92 @ikaruga921196
GH2D_REPLACE duncanyoyo1 @duncanyoyo1
GH2D_REPLACE GrumpyGopher @Bitter_Bizarro
GH2D_REPLACE hmcneill46 @harryarry
GH2D_REPLACE J0TK @j0tk
GH2D_REPLACE J0ttenmiller @j0tt
GH2D_REPLACE bcat @bcat
GH2D_REPLACE joyrider3774 @joyrider3774
GH2D_REPLACE nmqanh @nmqanh
GH2D_REPLACE Illumini85 @illumini_85
GH2D_REPLACE SamusAranX @gordenfreemant
GH2D_REPLACE solojazz @roastbean
GH2D_REPLACE xonglebongle @xonglebongle
GH2D_REPLACE yomama78 @yomama78

printf "\n\033[1mmuOS contributors from '%s' to '%s'\033[0m\n\t%s\n" \
	"$FROM_COMMIT" "$TO_COMMIT" "$(cat "$MU_UDIR/contributor.txt")"

printf "\n\033[1mDon't forget to format the changelog file... good luck!\033[0m\n\n"
