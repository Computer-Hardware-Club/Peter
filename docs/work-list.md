# Workshop work list

## Workshop reliability

- [x] Provision teams independently. A VM that fails to start or reach SSH should not block working logins for other teams. Show progress per team and offer a retry for the failed team.
- [x] Keep the roster visible when Guacamole is unavailable. Show which VMs are running, mark session status unknown when needed, and make the ready count and credential controls agree with the team cards.
- [x] Tie screen requests to the team's unique internal identity. Clear the panel when a slot is assigned to another team, discard responses for the previous team, and mark retained output stale if updates stop.

## Officer dashboard

- [x] Add a read-only **All terminals** view that fills the dashboard frame with live team screens. One team gets the full frame, two teams split it into halves, and three or four teams use a 2×2 grid. Use Guacamole’s graphical output so full-screen applications display correctly. Fit the dashboard to the viewport and keep team controls alongside the terminal heading.
- [x] Use the team number as the portal username and offer a **Copy password** button.

## Club VM template

- [x] Give interactive participant logins a clean terminal with a large ASCII **Computer Hardware Club** wordmark and a `team-N@peter` prompt. Use a compact wordmark for narrow terminals and avoid replaying the welcome on subshells.
- [x] Bundle Nano and `chcfetch` in the Debian template and give the participant terminal a modern palette.
