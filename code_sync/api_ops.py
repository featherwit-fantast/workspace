#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GitLab / Gitee HTTP API 客户端 — 所有脚本共用的唯一 API 层。
不依赖 git clone，通过 REST API 秒级完成操作。
"""

import json
import re
import sys
import time
import urllib.parse
import urllib.request
import urllib.error
from datetime import date, timedelta
from pathlib import Path

from logger import log


class APIError(Exception):
    def __init__(self, message: str):
        self.message = message
        super().__init__(message)


class GitLabAPI:
    """GitLab REST API v4 客户端"""

    TIMEOUT = 30

    def __init__(self, base_url: str, token: str):
        self.base_url = base_url.rstrip("/")
        self.token = token

    def _encode_project_path(self, repo_url: str) -> tuple[str, str]:
        """
        解析 GitLab 仓库 URL → (api_prefix, url_encoded_path)

        示例:
          http://git.xxx.com/gitlab/otc-dev/bond-calc.git
            → ("/gitlab", "otc-dev%2Fbond-calc")
          http://git.xxx.com/otc-dev/bond-calc.git
            → ("", "otc-dev%2Fbond-calc")
        """
        m = re.search(r"https?://[^/]+/(.+?)(?:\.git)?\s*$", repo_url)
        if not m:
            raise APIError(f"无法解析仓库 URL: {repo_url}")

        full_path = m.group(1)
        parts = full_path.split("/")

        if parts[0] == "gitlab":
            api_prefix = "/gitlab"
            project_path = "/".join(parts[1:])
        else:
            api_prefix = ""
            project_path = full_path

        encoded = project_path.replace("/", "%2F")
        return api_prefix, encoded

    def _api_get(self, url: str) -> tuple[dict | None, int, str]:
        """GET 请求，返回 (data | None, HTTP 状态码, 错误信息)。成功时 code=0, err=""."""
        headers = {"PRIVATE-TOKEN": self.token}
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=self.TIMEOUT) as resp:
                return json.loads(resp.read()), 0, ""
        except urllib.error.HTTPError as e:
            err = e.read().decode(errors="replace") if e.fp else ""
            return None, e.code, f"HTTP {e.code}: {err.strip()[:120]}"
        except urllib.error.URLError as e:
            return None, 0, f"网络错误: {e.reason}"
        except Exception as e:
            return None, 0, str(e)

    def _find_project_id_by_search(self, api_prefix: str, repo_name: str, full_path: str) -> int | None:
        """通过搜索查找项目 ID"""
        search_url = "{}/api/v4/projects?search={}&per_page=20".format(
            self.base_url + api_prefix,
            urllib.parse.quote(repo_name, safe='')
        )
        projects, code, err = self._api_get(search_url)
        if err and not projects:
            raise APIError("搜索项目失败: {}".format(err))

        for p in projects:
            if p.get("path_with_namespace") == full_path:
                return p["id"]
        return None

    def _get_branch_data(self, api_prefix: str, pid: int, branch: str) -> dict | None:
        """获取分支数据"""
        encoded_branch = urllib.parse.quote(branch, safe="")
        branch_url = "{}/api/v4/projects/{}/repository/branches/{}".format(
            self.base_url + api_prefix, pid, encoded_branch
        )
        data, code, err = self._api_get(branch_url)

        if err and not data:
            if code == 404:
                return None
            raise APIError("获取分支失败: {}".format(err))
        return data

    def _get_commit_info(self, api_prefix: str, pid: int, commit_sha: str, branch_data: dict) -> dict:
        """获取提交信息"""
        commit_url = "{}/api/v4/projects/{}/repository/commits/{}".format(
            self.base_url + api_prefix, pid, commit_sha
        )
        commit_data, code, err = self._api_get(commit_url)

        if commit_data:
            raw_message = commit_data.get("message") or ""
            full_sha = commit_data.get("id", "") or commit_sha
            return {
                "sha": full_sha,
                "message": raw_message.splitlines()[0] if raw_message else "(无提交信息)",
            }

        # 如果 commits API 失败，使用 branches API 中的数据
        fallback_message = branch_data.get("commit", {}).get("message") or ""
        full_sha = branch_data.get("commit", {}).get("id", "") or commit_sha
        return {
            "sha": full_sha,
            "message": fallback_message.splitlines()[0] if fallback_message else "(无法获取提交信息)",
        }

    def get_branch_commit(self, repo_url: str, branch: str) -> dict | None:
        """获取分支最新提交 → {"sha": str, "message": str}
        404 时返回 None（分支不存在）；其他 HTTP 错误抛 APIError。
        """
        api_prefix, encoded = self._encode_project_path(repo_url)
        repo_name = encoded.split("%2F")[-1]
        full_path = encoded.replace("%2F", "/")

        pid = self._find_project_id_by_search(api_prefix, repo_name, full_path)
        if pid is None:
            return None

        branch_data = self._get_branch_data(api_prefix, pid, branch)
        if branch_data is None:
            return None

        commit_sha = branch_data.get("commit", {}).get("id", "") or branch_data.get("commit", {}).get("short_id", "")
        if not commit_sha:
            return None

        return self._get_commit_info(api_prefix, pid, commit_sha, branch_data)

    def _request(self, method: str, url: str, data: dict | None = None) -> dict:
        headers = {"PRIVATE-TOKEN": self.token}
        if data is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(data).encode()
        else:
            body = None

        req = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=self.TIMEOUT) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            err_body = e.read().decode(errors="replace") if e.fp else ""
            if "already exists" in err_body:
                raise APIError("already_exists")
            raise APIError(f"HTTP {e.code}: {err_body}")
        except Exception as e:
            raise APIError(str(e))

    def find_project_id(self, repo_url: str) -> int:
        _, encoded = self._encode_project_path(repo_url)
        api_prefix, _ = self._encode_project_path(repo_url)
        url = f"{self.base_url}{api_prefix}/api/v4/projects/{encoded}"
        result = self._request("GET", url)
        return result["id"]

    def delete_tag(self, repo_url: str, tag_name: str) -> None:
        pid = self.find_project_id(repo_url)
        api_prefix, _ = self._encode_project_path(repo_url)
        encoded_tag = urllib.parse.quote(tag_name, safe="")
        url = f"{self.base_url}{api_prefix}/api/v4/projects/{pid}/repository/tags/{encoded_tag}"
        try:
            self._request("DELETE", url)
        except APIError:
            pass

    def create_tag(self, repo_url: str, tag_name: str, ref: str,
                   message: str = "") -> dict:
        pid = self.find_project_id(repo_url)
        api_prefix, _ = self._encode_project_path(repo_url)
        url = f"{self.base_url}{api_prefix}/api/v4/projects/{pid}/repository/tags"
        payload = {"tag_name": tag_name, "ref": ref}
        if message:
            payload["message"] = message
        return self._request("POST", url, payload)

    def create_branch(self, repo_url: str, branch_name: str, ref: str) -> dict:
        pid = self.find_project_id(repo_url)
        api_prefix, _ = self._encode_project_path(repo_url)
        url = f"{self.base_url}{api_prefix}/api/v4/projects/{pid}/repository/branches"
        return self._request("POST", url, {"branch": branch_name, "ref": ref})

    def list_branches(self, project_id: int) -> list[dict]:
        api_prefix = ""
        url = f"{self.base_url}{api_prefix}/api/v4/projects/{project_id}/repository/branches?per_page=100"
        try:
            return self._request("GET", url)
        except APIError:
            return []

    def list_tags(self, project_id: int) -> list[dict]:
        api_prefix = ""
        url = f"{self.base_url}{api_prefix}/api/v4/projects/{project_id}/repository/tags"
        try:
            return self._request("GET", url)
        except APIError:
            return []


class GiteeAPI:
    """Gitee / Gitee 私有版 REST API v5 客户端"""

    TIMEOUT = 30

    def __init__(self, base_url: str, token: str):
        self.base_url = base_url.rstrip("/")
        self.token = token

    def _extract_repo_path(self, repo_url: str) -> str:
        m = re.search(r"https?://[^/]+/(.+?)(?:\.git)?\s*$", repo_url)
        if not m:
            raise APIError(f"无法解析仓库 URL: {repo_url}")
        return m.group(1)

    def _request(self, method: str, url: str, data: dict | None = None) -> dict:
        headers = {"PRIVATE-TOKEN": self.token}
        if data is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(data).encode()
        else:
            body = None

        req = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=self.TIMEOUT) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            err_body = e.read().decode(errors="replace") if e.fp else ""
            raise APIError(f"HTTP {e.code}: {err_body}")
        except Exception as e:
            raise APIError(str(e))

    def create_tag(self, repo_url: str, name: str, sha: str) -> dict:
        repo_path = self._extract_repo_path(repo_url)
        url = f"{self.base_url}/api/v5/repos/{repo_path}/git/references"
        return self._request("POST", url, {"ref": f"refs/tags/{name}", "sha": sha})

    def create_branch(self, repo_url: str, name: str, sha: str) -> dict:
        repo_path = self._extract_repo_path(repo_url)
        url = f"{self.base_url}/api/v5/repos/{repo_path}/git/references"
        return self._request("POST", url, {"ref": f"refs/heads/{name}", "sha": sha})

    def _api_get(self, url: str) -> tuple[dict | None, int, str]:
        """GET 请求，返回 (data | None, HTTP 状态码, 错误信息)。成功时 code=0, err=""."""
        headers = {"PRIVATE-TOKEN": self.token}
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=self.TIMEOUT) as resp:
                return json.loads(resp.read()), 0, ""
        except urllib.error.HTTPError as e:
            err = e.read().decode(errors="replace") if e.fp else ""
            return None, e.code, f"HTTP {e.code}: {err.strip()[:120]}"
        except urllib.error.URLError as e:
            return None, 0, f"网络错误: {e.reason}"
        except Exception as e:
            return None, 0, str(e)

    def get_branch_commit(self, repo_url: str, branch: str) -> dict | None:
        """获取分支最新提交 → {"sha": str, "message": str}
        404 时返回 None（分支不存在）；其他 HTTP 错误抛 APIError。
        """
        repo_path = self._extract_repo_path(repo_url)
        encoded_branch = urllib.parse.quote(branch, safe="")
        
        # 先获取分支信息（确认分支存在并获取 sha）
        branch_url = f"{self.base_url}/api/v5/repos/{repo_path}/branches/{encoded_branch}"
        data, code, err = self._api_get(branch_url)
        if err and not data:
            if code == 404:
                return None
            raise APIError(f"获取分支失败: {err}")
        if not data:
            return None
            
        commit_sha = data.get("commit", {}).get("sha", "")
        if not commit_sha:
            return None
        
        # 通过 commits API 获取完整的 commit 信息
        commits_url = f"{self.base_url}/api/v5/repos/{repo_path}/commits/{commit_sha}"
        commit_data, code, err = self._api_get(commits_url)
        
        if commit_data:
            raw_message = commit_data.get("commit", {}).get("message") or ""
            return {
                "sha": commit_sha,
                "message": raw_message.splitlines()[0] if raw_message else "(无提交信息)",
            }
        
        # 如果 commits API 失败，至少返回 sha
        return {
            "sha": commit_sha,
            "message": "(无法获取提交信息)",
        }

    def get_default_branch_sha(self, repo_url: str) -> str | None:
        repo_path = self._extract_repo_path(repo_url)
        url = f"{self.base_url}/api/v5/repos/{repo_path}"
        try:
            data = self._request("GET", url)
            return data.get("commit", {}).get("sha")
        except APIError:
            return None


def default_tag_name() -> str:
    thu = date.today() + timedelta(days=(3 - date.today().weekday()))
    return f"glms/{thu.strftime('%Y%m%d')}"
